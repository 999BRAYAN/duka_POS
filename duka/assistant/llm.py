"""The optional free language model: Ollama (https://ollama.com), which runs on
this computer. Nothing here is needed for the assistant to work - without it
the built-in answers still cover the usual questions - but with it, a manager
can ask things the built-in answers don't know about.

Install Ollama, run `ollama pull qwen2.5:3b` (about 2 GB, once), and leave
Ollama running. The assistant finds it by itself; set DUKA_OLLAMA_MODEL to
choose a particular model, DUKA_OLLAMA_URL if it isn't on this computer's
default port, and DUKA_OLLAMA_TIMEOUT (seconds) if your computer is slow.
"""

import json
import os
import time
import urllib.request

_PREFER = ("qwen2.5-coder", "qwen2.5", "qwen3", "llama3", "mistral", "gemma", "phi")
_cache: dict = {"model": None, "at": 0.0}


def _url() -> str:
    return os.environ.get("DUKA_OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")


def _timeout() -> float:
    try:
        return float(os.environ.get("DUKA_OLLAMA_TIMEOUT", "90"))
    except ValueError:
        return 90.0


def model() -> str | None:
    """The model to use: the one named in DUKA_OLLAMA_MODEL, else the best one
    Ollama has installed. Re-checked every half minute so installing Ollama
    needs no restart of the shop software."""
    named = os.environ.get("DUKA_OLLAMA_MODEL")
    if named:
        return named
    now = time.monotonic()
    if now - _cache["at"] < (30 if _cache["model"] else 15):
        return _cache["model"]
    found = None
    try:
        with urllib.request.urlopen(f"{_url()}/api/tags", timeout=2) as r:
            names = [m["name"] for m in json.load(r).get("models", [])]
        for want in _PREFER:
            found = next((n for n in names if want in n.lower()), None)
            if found:
                break
        found = found or (names[0] if names else None)
    except Exception:
        found = None
    _cache.update(model=found, at=now)
    return found


def _keep_alive() -> str:
    """How long Ollama keeps the model in memory after a question (it unloads
    after 5 minutes by default, which makes the next question slow)."""
    return os.environ.get("DUKA_OLLAMA_KEEP_ALIVE", "24h")


def warm_up() -> None:
    """Load the model now, so the first question doesn't wait for it. Quiet
    when Ollama isn't there."""
    try:
        name = model()
        if name:
            body = json.dumps({"model": name, "keep_alive": _keep_alive()}).encode()
            req = urllib.request.Request(f"{_url()}/api/generate", body, {"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=300).read()
    except Exception:
        pass


def available() -> bool:
    return model() is not None


def chat(messages: list[dict], *, timeout: float | None = None, max_tokens: int | None = None) -> str:
    """One reply from the model; raises if Ollama isn't reachable."""
    body = json.dumps({
        "model": model(), "stream": False, "messages": messages,
        "options": {"temperature": 0, **({"num_predict": max_tokens} if max_tokens else {})}, "keep_alive": _keep_alive(),
    }).encode()
    req = urllib.request.Request(f"{_url()}/api/chat", body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout or _timeout()) as r:
        return json.load(r)["message"]["content"].strip()
