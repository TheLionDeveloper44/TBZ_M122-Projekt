# Author: TheLionDeveloper44
# Dieses Skript unterliegt der Lizenz, die in der LICENSE-Datei im Stammverzeichnis dieses Repositories enthalten ist.
# Ohne ausdrückliche schriftliche Genehmigung ist es untersagt, dieses Skript zu kopieren, zu modifizieren oder zu verbreiten.

# USE scoop search "APP NAME" to find apps

import subprocess
import json
from pathlib import Path
from typing import Iterable, Callable, Optional, List

_POWER_SHELL = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
_BUCKETS_INITIALIZED = False
_SEARCH_CACHE: dict[str, List[str]] = {}
_BUCKET_CACHE: dict[str, str] = {}
_BUCKET_LIST_CACHE: Optional[set[str]] = None

# Persistent cache configuration
# Caches are stored in the user's home directory under ".app_manager_cache"
_CACHE_DIR = Path.home() / ".app_manager_cache"
_SEARCH_CACHE_FILE = _CACHE_DIR / "search_cache.json"
_BUCKET_CACHE_FILE = _CACHE_DIR / "bucket_cache.json"
_BUCKET_LIST_CACHE_FILE = _CACHE_DIR / "bucket_list_cache.json"


def _ensure_cache_dir() -> None:
    """Ensure cache directory exists."""
    _CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _load_cache_from_disk() -> None:
    """Load all caches from disk on startup."""
    global _SEARCH_CACHE, _BUCKET_CACHE, _BUCKET_LIST_CACHE
    
    _ensure_cache_dir()
    
    # Load search cache
    if _SEARCH_CACHE_FILE.exists():
        try:
            with open(_SEARCH_CACHE_FILE, "r", encoding="utf-8") as f:
                _SEARCH_CACHE = json.load(f)
        except (json.JSONDecodeError, IOError):
            _SEARCH_CACHE = {}
    
    # Load bucket cache
    if _BUCKET_CACHE_FILE.exists():
        try:
            with open(_BUCKET_CACHE_FILE, "r", encoding="utf-8") as f:
                _BUCKET_CACHE = json.load(f)
        except (json.JSONDecodeError, IOError):
            _BUCKET_CACHE = {}
    
    # Load bucket list cache
    if _BUCKET_LIST_CACHE_FILE.exists():
        try:
            with open(_BUCKET_LIST_CACHE_FILE, "r", encoding="utf-8") as f:
                _BUCKET_LIST_CACHE = set(json.load(f))
        except (json.JSONDecodeError, IOError):
            _BUCKET_LIST_CACHE = None


def _save_search_cache() -> None:
    """Save search cache to disk."""
    _ensure_cache_dir()
    try:
        with open(_SEARCH_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(_SEARCH_CACHE, f, indent=2)
    except IOError:
        pass  # Silently fail if unable to write


def _save_bucket_cache() -> None:
    """Save bucket cache to disk."""
    _ensure_cache_dir()
    try:
        with open(_BUCKET_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(_BUCKET_CACHE, f, indent=2)
    except IOError:
        pass  # Silently fail if unable to write


def _save_bucket_list_cache() -> None:
    """Save bucket list cache to disk."""
    global _BUCKET_LIST_CACHE
    _ensure_cache_dir()
    try:
        with open(_BUCKET_LIST_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(list(_BUCKET_LIST_CACHE) if _BUCKET_LIST_CACHE else [], f, indent=2)
    except IOError:
        pass  # Silently fail if unable to write


# Load caches from disk on module import
_load_cache_from_disk()


def is_search_cached(term: str) -> bool:
    """Check if a search term is already cached."""
    return (term or "").strip() in _SEARCH_CACHE


def _emit(progress: Optional[Callable[[str], None]], message: str) -> None:
    if progress:
        progress(message)


def _run_ps(command: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        _POWER_SHELL + [command],
        check=True,
        capture_output=True,
        text=True,
    )


def ensure_scoop_available(progress: Optional[Callable[[str], None]] = None) -> None:
    _emit(progress, "Prüfe auf Scoop...")
    try:
        _run_ps("scoop --version")
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "Scoop ist nicht installiert. Bitte installieren Sie Scoop zuerst: https://scoop.sh/"
        ) from exc


def ensure_common_buckets(progress: Optional[Callable[[str], None]] = None) -> None:
    """Ensure common Scoop buckets are added for better search coverage (cached after first run)."""
    global _BUCKETS_INITIALIZED
    if _BUCKETS_INITIALIZED:
        return
    
    common_buckets = ["extras", "versions", "java", "games"]
    res = _run_ps("scoop bucket list")
    existing = {ln.strip().lower() for ln in res.stdout.splitlines() if ln.strip()}
    
    for bucket in common_buckets:
        if bucket not in existing:
            try:
                _emit(progress, f"Füge Bucket '{bucket}' für bessere Suchergebnisse hinzu...")
                _run_ps(f"scoop bucket add {bucket}")
            except subprocess.CalledProcessError:
                # Silently continue if bucket can't be added
                pass
    
    _BUCKETS_INITIALIZED = True


def search_apps(term: str, progress: Optional[Callable[[str], None]] = None) -> List[str]:
    global _SEARCH_CACHE, _BUCKET_CACHE
    term = (term or "").strip()
    if len(term) < 2:
        raise ValueError("Bitte mindestens 2 Zeichen für die Suche eingeben.")
    
    if term in _SEARCH_CACHE:
        _emit(progress, f"Suche nach '{term}' (cached)...")
        return _SEARCH_CACHE[term]
    
    ensure_scoop_available(progress)
    ensure_common_buckets(progress)
    _emit(progress, f"Suche nach '{term}' (Erstmalige Suche, Ergebnisse werden für schnellere zukünftige Suchen gecacht)...")
    try:
        result = _run_ps(f"scoop search {term}")
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else "unknown error"
        raise RuntimeError(f"Suche fehlgeschlagen: {stderr}") from exc

    apps: List[str] = []
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        low = stripped.lower()
        if "result" in low or stripped.startswith("-") or low.startswith("name"):
            continue
        token = stripped.split()[0]
        if "/" in token:
            bucket, name = token.split("/", 1)
            _BUCKET_CACHE[name.lower()] = bucket.lower()
            token = name
        if token:
            apps.append(token)

    if not apps:
        raise RuntimeError(f"Keine Treffer für '{term}' gefunden.")
    
    result_list = sorted(dict.fromkeys(apps))
    _SEARCH_CACHE[term] = result_list
    _save_search_cache()
    _save_bucket_cache()
    return result_list


def _discover_bucket_for_app(app: str, progress: Optional[Callable[[str], None]] = None) -> Optional[str]:
    global _BUCKET_CACHE
    app_lower = app.lower()
    
    if app_lower in _BUCKET_CACHE:
        bucket = _BUCKET_CACHE[app_lower]
        _emit(progress, f"Bucket für {app} (gecacht): {bucket}")
        return bucket
    
    try:
        res = _run_ps(f"scoop search {app}")
    except subprocess.CalledProcessError:
        return None
    buckets = set()
    for line in res.stdout.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        low = stripped.lower()
        if "result" in low or stripped.startswith("-") or low.startswith("name"):
            continue
        token = stripped.split()[0]
        if "/" in token:
            bucket, name = token.split("/", 1)
            if name.lower() == app_lower:
                buckets.add(bucket.lower())
                _BUCKET_CACHE[app_lower] = bucket.lower()
    if buckets:
        chosen = sorted(buckets)[0]
        _emit(progress, f"Bucket für {app} gefunden: {chosen}")
        return chosen
    return None


def ensure_bucket(bucket: str, progress: Optional[Callable[[str], None]] = None) -> None:
    global _BUCKET_LIST_CACHE
    
    if _BUCKET_LIST_CACHE is None:
        res = _run_ps("scoop bucket list")
        _BUCKET_LIST_CACHE = {ln.strip().lower() for ln in res.stdout.splitlines() if ln.strip()}
        _save_bucket_list_cache()
    
    if bucket.lower() not in _BUCKET_LIST_CACHE:
        _emit(progress, f"Füge Bucket '{bucket}' hinzu...")
        try:
            _run_ps(f"scoop bucket add {bucket}")
            _BUCKET_LIST_CACHE.add(bucket.lower())
            _save_bucket_list_cache()
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.strip() if exc.stderr else "unknown error"
            raise RuntimeError(f"Bucket '{bucket}' konnte nicht hinzugefügt werden: {stderr}") from exc


def install_apps(apps: Iterable[str], progress: Optional[Callable[[str], None]] = None) -> None:
    apps = list(apps)
    if not apps:
        return
    ensure_scoop_available(progress)
    for app in apps:
        bucket = _discover_bucket_for_app(app, progress)
        if bucket:
            ensure_bucket(bucket, progress)
        _emit(progress, f"Installiere {app}...")
        try:
            _run_ps(f"scoop install {app}")
            _emit(progress, f"✓ {app} installiert.")
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.strip() if exc.stderr else ""
            stdout = exc.stdout.strip() if exc.stdout else ""
            detail = stderr or stdout or "unbekannter Fehler"
            raise RuntimeError(f"Installation von {app} fehlgeschlagen: {detail}") from exc
    _emit(progress, "Alle ausgewählten Apps verarbeitet.")


def list_installed_apps(progress: Optional[Callable[[str], None]] = None) -> List[str]:
    """List all currently installed scoop applications."""
    ensure_scoop_available(progress)
    _emit(progress, "Liste installierte Apps auf...")
    try:
        result = _run_ps("scoop list")
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else "unbekannter Fehler"
        raise RuntimeError(f"Fehler beim Auflisten der Apps: {stderr}") from exc
    
    apps: List[str] = []
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        low = stripped.lower()
        # Skip header lines, separators, and column headers
        if "name" in low or "installed" in low or stripped.startswith("-"):
            continue
        # Extract app name (first token before whitespace)
        token = stripped.split()[0]
        if token:
            apps.append(token)
    
    return apps


def uninstall_apps(apps: Iterable[str], progress: Optional[Callable[[str], None]] = None) -> None:
    """Uninstall the specified scoop applications."""
    apps = list(apps)
    if not apps:
        return
    ensure_scoop_available(progress)
    for app in apps:
        _emit(progress, f"Deinstalliere {app}...")
        try:
            _run_ps(f"scoop uninstall {app}")
            _emit(progress, f"✓ {app} deinstalliert.")
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.strip() if exc.stderr else ""
            stdout = exc.stdout.strip() if exc.stdout else ""
            detail = stderr or stdout or "unbekannter Fehler"
            raise RuntimeError(f"Deinstallation von {app} fehlgeschlagen: {detail}") from exc
    _emit(progress, "Alle ausgewählten Apps deinstalliert.")
