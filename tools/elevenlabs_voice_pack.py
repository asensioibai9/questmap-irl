#!/usr/bin/env python3
"""Paquetes de voz de navegación generados con la API OFICIAL de ElevenLabs (solo biblioteca estándar + ffmpeg).

La clave se lee de la variable de entorno ELEVENLABS_API_KEY. Nunca se escribe en disco, en el estado ni en los logs.
A ElevenLabs solo se envían las frases FIJAS del manifiesto: ninguna ubicación, ruta, destino ni dato del usuario.

Comandos (sin clave):
  check-catalog          Comprueba que el manifiesto coincide con VoicePromptCatalog.swift.
  estimate               Caracteres y créditos estimados (muestras y paquetes completos).
  verify   --pack ID     Analiza los audios maestros (duración, silencios, cortes, volumen).
  review   --pack ID     Crea una página HTML de preescucha con avisos.
  approve  --pack ID     Marca como aprobados los audios revisados (no se vuelven a sobrescribir).
  build    --pack ID     Codifica a AAC (.m4a) los audios VÁLIDOS y escribe el índice del paquete en la app.

Comandos que consumen la API (piden confirmación con el coste antes de enviar nada):
  account                Plan y créditos restantes (no consume créditos).
  voices                 Lista voces disponibles en español (no consume créditos).
  samples  --voice ID…   Unas pocas frases de prueba por voz candidata, para elegir.
  generate --pack ID     Genera las frases que falten o no sean válidas (reanudable).
"""
from __future__ import annotations

import argparse
import concurrent.futures as futures
import hashlib
import html
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
from array import array
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK_DIR = ROOT / "tools" / "voice_packs"
MANIFEST = PACK_DIR / "manifest.json"
PACKS = PACK_DIR / "packs.json"
WORK = PACK_DIR / "work"                      # maestros, estado y preescucha (fuera de git)
APP_RESOURCES = ROOT / "QuestMapIRL" / "Resources" / "VoicePacks"
CATALOG_SWIFT = ROOT / "QuestMapIRL" / "Domain" / "Voice" / "VoicePromptCatalog.swift"
API = "https://api.elevenlabs.io"
MAX_WORKERS = 2                               # por debajo de la concurrencia del plan gratuito (2 en Multilingual v2)
MAX_ATTEMPTS = 4
SAMPLE_RATE = 24000

# Umbrales de calidad (sobre PCM 16 bits mono)
SILENCE_DBFS = -45.0
TARGET_RMS_DBFS = -20.0
MIN_DURATION, MAX_DURATION = 0.35, 6.0
MAX_LEAD_SILENCE, MAX_TAIL_SILENCE = 0.6, 0.9


# ---------------------------------------------------------------- utilidades

def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)                     # escritura atómica: un corte no deja el estado a medias


def manifest():
    return load_json(MANIFEST)


def pack_config(pack_id: str):
    for pack in load_json(PACKS)["packs"]:
        if pack["id"] == pack_id:
            return pack
    sys.exit(f"Paquete desconocido: {pack_id}")


def api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key:
        sys.exit("Falta la variable de entorno ELEVENLABS_API_KEY (no la pegues en el chat ni en el código).")
    return key


def phrase_context(phrase, mf):
    """Contexto de entonación: las distancias se dicen como inicio de frase y las maniobras como continuación."""
    if not phrase.get("fragment"):
        return None, None
    if phrase.get("kind") == "distance":
        return None, mf["context"]["distance_next_text"]
    return mf["context"]["maneuver_previous_text"], None


def request_body(text, gen, previous_text=None, next_text=None):
    body = {"text": text, "model_id": gen["model_id"], "voice_settings": gen["voice_settings"],
            "seed": gen["seed"], "apply_text_normalization": gen["apply_text_normalization"]}
    if previous_text:
        body["previous_text"] = previous_text
    if next_text:
        body["next_text"] = next_text
    return body


def config_hash(voice_id, body, output_format) -> str:
    blob = json.dumps({"voice": voice_id, "body": body, "format": output_format}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_name(phrase_id: str) -> str:
    return phrase_id.replace(".", "_")


# ---------------------------------------------------------------- API

class ApiError(Exception):
    def __init__(self, status, message, retryable, retry_after=None):
        super().__init__(message)
        self.status, self.retryable, self.retry_after = status, retryable, retry_after


def api_request(method, path, key, query=None, body=None, timeout=60):
    url = API + path + ("?" + urllib.parse.urlencode(query, doseq=True) if query else "")
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("xi-api-key", key)
    req.add_header("User-Agent", "voice-pack-tool/1.0")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.headers.get("Content-Type", ""), resp.read()
    except urllib.error.HTTPError as err:
        raw = err.read()[:2000]
        try:
            detail = json.loads(raw).get("detail")
            message = detail.get("message") if isinstance(detail, dict) else str(detail)
        except (ValueError, AttributeError):
            message = raw.decode("utf-8", "replace")[:200]
        retry_after = err.headers.get("Retry-After")
        retryable = err.code == 429 or err.code >= 500
        raise ApiError(err.code, f"HTTP {err.code}: {message}", retryable,
                       float(retry_after) if retry_after and retry_after.isdigit() else None) from None
    except (urllib.error.URLError, TimeoutError) as err:
        raise ApiError(None, f"Red: {err}", True) from None


def synthesize(key, voice_id, body, output_format) -> bytes:
    """Una frase. Reintentos limitados con espera creciente; nunca devuelve un cuerpo de error como audio."""
    last = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            status, ctype, payload = api_request("POST", f"/v1/text-to-speech/{urllib.parse.quote(voice_id)}", key,
                                                 query={"output_format": output_format}, body=body, timeout=90)
            if "json" in ctype or "text" in ctype:
                raise ApiError(status, f"Respuesta no es audio ({ctype})", False)
            if output_format.startswith("pcm_") and (len(payload) < SAMPLE_RATE // 5 or len(payload) % 2):
                raise ApiError(status, f"PCM inválido ({len(payload)} bytes)", True)
            return payload
        except ApiError as err:
            last = err
            if not err.retryable or attempt == MAX_ATTEMPTS:
                break
            time.sleep(err.retry_after or min(30, 2 ** attempt))
    raise last


# Errores que afectan a TODO el lote (clave, plan, permisos): se para en el primero en vez de repetirlo 40 veces.
BLOCKING_STATUS = {401, 402, 403}


def blocking_message(err: ApiError) -> str:
    hints = {401: "La clave no es válida o no tiene permiso de Text to Speech.",
             402: "Tu plan no permite esta voz o te faltan créditos (las voces de la biblioteca exigen plan de pago).",
             403: "La clave no tiene permiso para esta operación."}
    return f"Lote detenido: {err}\n{hints.get(err.status, '')} No se ha enviado nada más."


def stop_pending(jobs) -> None:
    for item in jobs:
        job = item[1] if isinstance(item, tuple) else item
        job.cancel()


def confirm(prompt: str, assume_yes: bool) -> None:
    print(prompt)
    if assume_yes:
        return
    if input("¿Continuar? Escribe «si»: ").strip().lower() not in ("si", "sí"):
        sys.exit("Cancelado: no se ha enviado nada.")


def subscription(key):
    _, _, raw = api_request("GET", "/v1/user/subscription", key)
    return json.loads(raw)


def remaining_credits(key):
    sub = subscription(key)
    return sub.get("tier"), sub.get("character_limit", 0) - sub.get("character_count", 0)


# ---------------------------------------------------------------- audio

def write_wav(path: Path, pcm: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp.wav")
    with wave.open(str(tmp), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm)
    os.replace(tmp, path)


def analyze(path: Path) -> dict:
    """Mide de verdad la señal: no es una escucha. Devuelve tiempos de voz, niveles y avisos."""
    try:
        with wave.open(str(path), "rb") as wav:
            if wav.getnchannels() != 1 or wav.getsampwidth() != 2:
                return {"valid": False, "issues": ["formato inesperado"]}
            rate = wav.getframerate()
            samples = array("h", wav.readframes(wav.getnframes()))
    except (wave.Error, EOFError, OSError) as err:
        return {"valid": False, "issues": [f"no es un WAV legible: {err}"]}
    if sys.byteorder == "big":
        samples.byteswap()
    n = len(samples)
    duration = n / rate
    window = int(rate * 0.01)
    frames_db = []
    for i in range(0, n - window + 1, window):
        chunk = samples[i:i + window]
        rms = math.sqrt(sum(s * s for s in chunk) / window) / 32768
        frames_db.append(20 * math.log10(rms) if rms > 0 else -120.0)
    loud = [i for i, db in enumerate(frames_db) if db > SILENCE_DBFS]
    issues = []
    if not loud:
        return {"valid": False, "duration": round(duration, 3), "issues": ["sin voz (silencio)"]}
    start = loud[0] * 0.01
    end = (loud[-1] + 1) * 0.01
    speech = samples[int(start * rate):int(end * rate)]
    peak = max(abs(s) for s in speech) / 32768
    rms = math.sqrt(sum(s * s for s in speech) / max(1, len(speech))) / 32768
    rms_db = 20 * math.log10(rms) if rms > 0 else -120.0
    gain = 10 ** ((TARGET_RMS_DBFS - rms_db) / 20)
    gain = max(0.5, min(2.5, gain, 0.97 / peak if peak > 0 else 2.5))
    if duration < MIN_DURATION or duration > MAX_DURATION:
        issues.append(f"duración rara ({duration:.2f} s)")
    if start > MAX_LEAD_SILENCE:
        issues.append(f"silencio inicial largo ({start:.2f} s)")
    if duration - end > MAX_TAIL_SILENCE:
        issues.append(f"silencio final largo ({duration - end:.2f} s)")
    if frames_db and frames_db[0] > SILENCE_DBFS + 10:
        issues.append("posible corte al principio (empieza con voz)")
    if frames_db and frames_db[-1] > SILENCE_DBFS + 10:
        issues.append("posible corte al final (termina con voz)")
    if peak >= 0.999:
        issues.append("saturación")
    # Márgenes de 40 ms para no comerse consonantes suaves al recortar.
    return {"valid": not any(i.startswith(("sin voz", "duración", "posible corte", "saturación")) for i in issues),
            "duration": round(duration, 3), "speech_start": round(max(0.0, start - 0.04), 3),
            "speech_end": round(min(duration, end + 0.04), 3), "peak_dbfs": round(20 * math.log10(peak), 1),
            "rms_dbfs": round(rms_db, 1), "gain": round(gain, 3), "issues": issues}


# ---------------------------------------------------------------- estado

def pack_work(pack_id):
    return WORK / pack_id


def load_state(pack_id):
    path = pack_work(pack_id) / "state.json"
    return load_json(path) if path.exists() else {"phrases": {}}


def load_approved(pack_id):
    path = pack_work(pack_id) / "approved.json"
    return load_json(path) if path.exists() else {}


# ---------------------------------------------------------------- comandos

def cmd_check_catalog(_args):
    source = CATALOG_SWIFT.read_text(encoding="utf-8")
    cases = dict(re.findall(r'case (\w+) = "([^"]+)"', source))
    phrases = re.findall(r'VoicePhrase\(id: \.(\w+), text: "([^"]+)",.*?required: (true|false)', source)
    swift = {cases[name]: (text, req == "true") for name, text, req in phrases}
    mine = {p["id"]: (p["text"], p["required"]) for p in manifest()["phrases"]}
    problems = [f"falta en el manifiesto: {k}" for k in swift if k not in mine]
    problems += [f"sobra en el manifiesto: {k}" for k in mine if k not in swift]
    problems += [f"distinto: {k} {mine[k]} ≠ {swift[k]}" for k in mine if k in swift and mine[k] != swift[k]]
    if problems:
        sys.exit("\n".join(problems))
    print(f"OK: {len(mine)} frases coinciden con VoicePromptCatalog.swift")


def count_chars(texts):
    return sum(len(t) for t in texts)


def cmd_estimate(_args):
    mf = manifest()
    full = count_chars(p["text"] for p in mf["phrases"])
    by_id = {p["id"]: p for p in mf["phrases"]}
    sample = count_chars(by_id[i]["text"] for i in mf["sample_phrases"])
    req = sum(1 for p in mf["phrases"] if p["required"])
    print(f"Frases: {len(mf['phrases'])} ({req} obligatorias) por paquete")
    print(f"Caracteres por paquete: {full}  ·  dos paquetes: {2 * full}")
    print(f"Muestras: {len(mf['sample_phrases'])} frases = {sample} caracteres por voz candidata")
    print("Multilingual v2 = 1 crédito por carácter (página de precios). El contexto previous/next_text no se cuenta aquí.")


def cmd_account(_args):
    key = api_key()
    sub = subscription(key)
    left = sub.get("character_limit", 0) - sub.get("character_count", 0)
    print(f"Plan: {sub.get('tier')} · estado: {sub.get('status')} · créditos restantes: {left}")
    if sub.get("tier") == "free":
        print("AVISO: el plan gratuito solo permite uso NO comercial (Términos 1(c)(i)). Sirve para muestras de prueba;"
              " el paquete que se distribuya en la app debe generarse con un plan de pago.")


def cmd_voices(args):
    key = api_key()
    # Sin filtro de idioma: las voces predefinidas suelen etiquetarse «en» aunque el modelo multilingüe hable español.
    # El español se marca con 'verified_languages' y las etiquetas.
    token, rows = None, []
    while True:
        query = {"page_size": 100}
        if args.category:
            query["category"] = args.category
        if token:
            query["next_page_token"] = token
        _, _, raw = api_request("GET", "/v2/voices", key, query=query)
        data = json.loads(raw)
        rows += data.get("voices", [])
        token = data.get("next_page_token")
        if not data.get("has_more") or not token:
            break
    def spanish_mark(v):
        verified = v.get("verified_languages") or []
        if any((l.get("locale") or "").lower() in ("es-es", "es_es") for l in verified):
            return "ES-ESPAÑA"
        labels = " ".join(str(x).lower() for x in (v.get("labels") or {}).values())
        if any(w in labels for w in ("spain", "peninsular", "castilian", "castellano", "españa")):
            return "ES-ESPAÑA?"
        if any(l.get("language") == "es" for l in verified) or "spanish" in labels:
            return "ES"
        return "-"

    rows.sort(key=lambda v: ({"ES-ESPAÑA": 0, "ES-ESPAÑA?": 1, "ES": 2}.get(spanish_mark(v), 3), v.get("name") or ""))
    for v in rows:
        labels = v.get("labels") or {}
        langs = ", ".join(f"{l.get('language')}/{l.get('locale') or l.get('accent') or '-'}"
                          for l in v.get("verified_languages") or [])
        print(f"[{spanish_mark(v):10}] {v['voice_id']}  {v.get('name')!r}  cat={v.get('category')}  "
              f"gender={labels.get('gender')}  accent={labels.get('accent')}  age={labels.get('age')}  "
              f"use={labels.get('use_case') or labels.get('use case')}  verified=[{langs}]")
    print(f"{len(rows)} voces de tu cuenta. Las de la biblioteca aparecen aquí solo después de añadirlas desde la web.")


def cmd_samples(args):
    key = api_key()
    mf = manifest()
    gen = load_json(PACKS)["packs"][0]["generation"]          # mismos ajustes que los paquetes
    by_id = {p["id"]: p for p in mf["phrases"]}
    chars = count_chars(by_id[i]["text"] for i in mf["sample_phrases"]) * len(args.voice)
    tier, left = remaining_credits(key)
    confirm(f"Muestras: {len(mf['sample_phrases'])} frases × {len(args.voice)} voces = {chars} caracteres "
            f"(plan {tier}, quedan {left}).", args.yes)
    out = WORK / "samples"
    jobs = []
    with futures.ThreadPoolExecutor(MAX_WORKERS) as pool:
        for voice in args.voice:
            for pid in mf["sample_phrases"]:
                phrase = by_id[pid]
                prev, nxt = phrase_context(phrase, mf)
                body = request_body(phrase["text"], gen, prev, nxt)
                path = out / voice / f"{safe_name(pid)}.wav"
                if path.exists():
                    continue
                jobs.append((path, pool.submit(synthesize, key, voice, body, gen["output_format"])))
        for path, job in jobs:
            try:
                write_wav(path, job.result())
                print("ok", path.relative_to(ROOT))
            except ApiError as err:
                print("ERROR", path.relative_to(ROOT), err)
                if err.status in BLOCKING_STATUS:
                    stop_pending(jobs)
                    sys.exit(blocking_message(err))
    write_samples_page(args.voice, mf)


def write_samples_page(voices, mf):
    by_id = {p["id"]: p for p in mf["phrases"]}
    rows = []
    for voice in voices:
        cells = "".join(
            f"<td>{html.escape(by_id[pid]['text'])}<br><audio controls preload=none src='{voice}/{safe_name(pid)}.wav'></audio></td>"
            for pid in mf["sample_phrases"])
        rows.append(f"<tr><th>{html.escape(voice)}</th>{cells}</tr>")
    page = ("<!doctype html><meta charset=utf-8><title>Muestras de voz</title><style>body{font:14px system-ui;margin:16px}"
            "td,th{border:1px solid #ccc;padding:6px;vertical-align:top}</style><h1>Muestras de voces candidatas</h1>"
            "<p>Mismas frases y ajustes para todas. Escucha con el volumen del coche en mente.</p><table>"
            + "".join(rows) + "</table>")
    (WORK / "samples").mkdir(parents=True, exist_ok=True)
    (WORK / "samples" / "index.html").write_text(page, encoding="utf-8")
    print("Preescucha:", (WORK / "samples" / "index.html"))


def cmd_generate(args):
    pack = pack_config(args.pack)
    if not pack.get("voice_id"):
        sys.exit("Este paquete aún no tiene voice_id en packs.json: elige la voz con 'voices' y 'samples' primero.")
    key = api_key()
    mf = manifest()
    gen = pack["generation"]
    work = pack_work(args.pack)
    state = load_state(args.pack)
    approved = load_approved(args.pack)
    todo = []
    for phrase in mf["phrases"]:
        prev, nxt = phrase_context(phrase, mf)
        body = request_body(phrase["text"], gen, prev, nxt)
        digest = config_hash(pack["voice_id"], body, gen["output_format"])
        master = work / "master" / f"{safe_name(phrase['id'])}.wav"
        entry = state["phrases"].get(phrase["id"], {})
        if phrase["id"] in approved:
            if approved[phrase["id"]].get("config") != digest:
                print(f"aviso: {phrase['id']} está aprobada con otra configuración; no se toca (desaprueba para regenerar)")
            continue
        if master.exists() and entry.get("config") == digest and entry.get("status") == "valid":
            continue
        todo.append((phrase, body, digest, master))
    if not todo:
        print("Nada que generar: todo está generado y validado.")
        return
    chars = count_chars(p["text"] for p, *_ in todo)
    tier, left = remaining_credits(key)
    if tier == "free":
        print("AVISO: plan gratuito = solo uso no comercial. No distribuyas este paquete en la app.")
    if chars > left:
        sys.exit(f"Faltan créditos: se necesitan ~{chars} y quedan {left}.")
    confirm(f"{pack['id']}: {len(todo)} frases, {chars} caracteres (plan {tier}, quedan {left}).", args.yes)
    with futures.ThreadPoolExecutor(MAX_WORKERS) as pool:
        jobs = {pool.submit(synthesize, key, pack["voice_id"], body, gen["output_format"]): (phrase, digest, master)
                for phrase, body, digest, master in todo}
        for job in futures.as_completed(jobs):
            phrase, digest, master = jobs[job]
            entry = {"config": digest, "updated": datetime.now(timezone.utc).isoformat(timespec="seconds")}
            try:
                pcm = job.result()
                staging = work / "staging" / master.name
                write_wav(staging, pcm)
                report = analyze(staging)
                if report["valid"]:
                    os.replace(staging, master)          # solo un audio VÁLIDO sustituye al maestro anterior
                    entry.update(status="valid", sha256=sha256_file(master), analysis=report)
                else:
                    entry.update(status="invalid", analysis=report)     # se conserva en staging para revisarlo
                print(entry["status"], phrase["id"], "; ".join(report.get("issues", [])))
            except ApiError as err:
                entry.update(status="error", error=str(err))           # el mensaje no contiene la clave
                print("ERROR", phrase["id"], err)
                if err.status in BLOCKING_STATUS:
                    state["phrases"][phrase["id"]] = entry
                    save_json(work / "state.json", state)
                    stop_pending(list(jobs))
                    sys.exit(blocking_message(err))
            state["phrases"][phrase["id"]] = entry
            save_json(work / "state.json", state)                   # se guarda tras cada frase: reanudable
    state["pack"] = {"id": pack["id"], "voice_id": pack["voice_id"], "voice_name": pack.get("voice_name"),
                     "generation": gen}
    save_json(work / "state.json", state)


def cmd_verify(args):
    work = pack_work(args.pack)
    mf = manifest()
    missing_required, bad = [], []
    for phrase in mf["phrases"]:
        master = work / "master" / f"{safe_name(phrase['id'])}.wav"
        if not master.exists():
            (missing_required if phrase["required"] else bad).append(f"falta {phrase['id']}")
            continue
        report = analyze(master)
        flag = "OK " if report["valid"] and not report["issues"] else ("AVISO" if report["valid"] else "MAL")
        print(f"{flag} {phrase['id']:24} {report.get('duration', 0):5.2f}s  voz {report.get('speech_start')}–"
              f"{report.get('speech_end')}  rms {report.get('rms_dbfs')} dBFS  ganancia {report.get('gain')}  "
              + "; ".join(report["issues"]))
        if not report["valid"]:
            (missing_required if phrase["required"] else bad).append(f"inválido {phrase['id']}")
    print("Comprobación de señal (no es una escucha): revisa pronunciación con 'review'.")
    if missing_required:
        sys.exit("Obligatorias sin audio válido: " + ", ".join(missing_required))


def cmd_review(args):
    work = pack_work(args.pack)
    mf = manifest()
    approved = load_approved(args.pack)
    focus = ("Incorpórate", "bifurcación", "rotonda", "metros", "kilómetro", "primera", "segunda", "tercera",
             "cuarta", "quinta", "sexta")
    rows = []
    for phrase in mf["phrases"]:
        name = f"{safe_name(phrase['id'])}.wav"
        master = work / "master" / name
        report = analyze(master) if master.exists() else {"issues": ["falta"], "valid": False}
        attention = any(f.lower() in phrase["text"].lower() for f in focus)
        rows.append(
            f"<tr class='{'bad' if not report['valid'] else ''}'><td><code>{phrase['id']}</code></td>"
            f"<td>{'★ ' if attention else ''}{html.escape(phrase['text'])}{' (obligatoria)' if phrase['required'] else ''}</td>"
            f"<td>{'<audio controls preload=none src=master/' + name + '></audio>' if master.exists() else '—'}</td>"
            f"<td>{report.get('duration', '')}</td><td>{html.escape('; '.join(report['issues']))}</td>"
            f"<td>{'aprobada' if phrase['id'] in approved else ''}</td></tr>")
    page = ("<!doctype html><meta charset=utf-8><title>Preescucha del paquete</title><style>body{font:14px system-ui;margin:16px}"
            "td{border-bottom:1px solid #ddd;padding:4px 8px}.bad{background:#fde2e2}</style>"
            f"<h1>{html.escape(args.pack)}</h1><p>★ = revisar con atención (incorpórate, bifurcación, rotonda, "
            "distancias, ordinales). Las columnas de avisos vienen de medir la señal, no de escucharla.</p>"
            "<table><tr><th>ID</th><th>Frase</th><th>Audio</th><th>s</th><th>Avisos</th><th>Estado</th></tr>"
            + "".join(rows) + "</table>")
    out = work / "review.html"
    out.write_text(page, encoding="utf-8")
    print("Preescucha:", out)


def cmd_approve(args):
    work = pack_work(args.pack)
    state = load_state(args.pack)
    approved = load_approved(args.pack)
    ids = args.ids or [p["id"] for p in manifest()["phrases"]]
    for pid in ids:
        entry = state["phrases"].get(pid)
        master = work / "master" / f"{safe_name(pid)}.wav"
        if not entry or entry.get("status") != "valid" or not master.exists():
            print("no se aprueba (sin audio válido):", pid)
            continue
        approved[pid] = {"config": entry["config"], "sha256": sha256_file(master),
                         "approved": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    for pid in args.revoke or []:
        approved.pop(pid, None)
    save_json(work / "approved.json", approved)
    print(f"Aprobadas: {len(approved)}")


def ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if not exe:
        sys.exit("Falta ffmpeg en el PATH (necesario para codificar a AAC).")
    return exe


def cmd_build(args):
    pack = pack_config(args.pack)
    work = pack_work(args.pack)
    mf = manifest()
    state = load_state(args.pack)
    approved = load_approved(args.pack)
    out_dir = APP_RESOURCES
    out_dir.mkdir(parents=True, exist_ok=True)
    phrases, missing = {}, []
    for phrase in mf["phrases"]:
        master = work / "master" / f"{safe_name(phrase['id'])}.wav"
        if not master.exists() or state["phrases"].get(phrase["id"], {}).get("status") != "valid":
            missing.append(phrase["id"])
            continue
        if args.require_approval and phrase["id"] not in approved:
            missing.append(phrase["id"])
            continue
        if phrase["id"] in approved and approved[phrase["id"]]["sha256"] != sha256_file(master):
            sys.exit(f"{phrase['id']}: el maestro no coincide con el aprobado. No se empaqueta.")
        report = analyze(master)
        file_name = f"{pack['slug']}-{safe_name(phrase['id'])}.m4a"   # nombre único: el bundle se copia plano
        target = out_dir / file_name
        subprocess.run([ffmpeg(), "-y", "-loglevel", "error", "-i", str(master), "-map_metadata", "-1",
                        "-c:a", "aac", "-b:a", "64k", "-ar", str(SAMPLE_RATE), "-ac", "1", str(target)], check=True)
        phrases[phrase["id"]] = {"file": file_name, "start": report["speech_start"], "end": report["speech_end"],
                                 "gain": report["gain"], "bytes": target.stat().st_size}
    required_missing = [p["id"] for p in mf["phrases"] if p["required"] and p["id"] in missing]
    index = {
        "format": 1, "id": pack["id"], "display_name": pack["display_name"], "language": pack["language"],
        "language_label": pack["language_label"], "description": pack["description"],
        "catalog_version": mf["catalog_version"], "provider": "ElevenLabs",
        "voice_id": pack["voice_id"], "voice_name": pack.get("voice_name"), "generation": pack["generation"],
        "built": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "phrases": phrases, "missing": missing,
    }
    save_json(out_dir / f"{pack['slug']}.voicepack.json", index)
    total = sum(p["bytes"] for p in phrases.values())
    print(f"{pack['id']}: {len(phrases)} archivos, {total / 1024:.0f} KB. Faltan: {missing or 'ninguna'}")
    if required_missing:
        print("AVISO: faltan obligatorias; la app mostrará el paquete como NO disponible:", required_missing)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check-catalog").set_defaults(fn=cmd_check_catalog)
    sub.add_parser("estimate").set_defaults(fn=cmd_estimate)
    sub.add_parser("account").set_defaults(fn=cmd_account)
    p = sub.add_parser("voices")
    p.add_argument("--category", choices=["premade", "cloned", "generated", "professional"])
    p.set_defaults(fn=cmd_voices)
    p = sub.add_parser("samples")
    p.add_argument("--voice", nargs="+", required=True)
    p.add_argument("--yes", action="store_true")
    p.set_defaults(fn=cmd_samples)
    for name, fn in (("generate", cmd_generate), ("verify", cmd_verify), ("review", cmd_review),
                     ("approve", cmd_approve), ("build", cmd_build)):
        p = sub.add_parser(name)
        p.add_argument("--pack", required=True)
        if name == "generate":
            p.add_argument("--yes", action="store_true")
        if name == "approve":
            p.add_argument("ids", nargs="*")
            p.add_argument("--revoke", nargs="*")
        if name == "build":
            p.add_argument("--require-approval", action="store_true")
        p.set_defaults(fn=fn)
    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
