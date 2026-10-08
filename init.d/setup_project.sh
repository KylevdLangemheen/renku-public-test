#!/bin/bash
# init.d/setup_project.sh: public file, contains no secrets. Never blocks session start.
_sp_main() {
  local LOG="$HOME/setup_project.log" root="${RENKU_WORKING_DIR:-/home/renku/work}" dir="${CODE_ACCESS_DIR:-}"
  local i f line tok url name dest helper venv py
  local -a uvargs=()
  _sp_log() { echo "[$(date +%T)] $*" >> "$LOG"; }
  venv="${UV_PROJECT_ENVIRONMENT:-$root/.venv}"
  _sp_log "start: user=$(id -un) pwd=$PWD root=$root git=$(command -v git || echo missing) uv=$(command -v uv || echo missing) venv=$venv ($([ -x "$venv/bin/python" ] && echo present || echo absent))"

  # wait for the password-protected drive mount and auto-detect its folder
  for i in $(seq 1 20); do
    [ -n "$dir" ] && [ -r "$dir/code_token" ] && break
    f=$(find "$root" -maxdepth 2 -name code_token 2>/dev/null | head -n1)
    if [ -n "$f" ]; then dir=$(dirname "$f"); break; fi
    sleep 1
  done
  _sp_log "work dir contains: $(ls "$root" 2>&1 | tr '\n' ' ')"
  if [ ! -r "$dir/code_token" ]; then _sp_log "access folder not mounted, skipping"; return 0; fi
  _sp_log "access folder: $dir"

  # env vars for terminals: read at shell start, values never stored
  touch "$HOME/.bashrc"
  for line in \
    'if [ -r "DIR/.env" ]; then set -a; . <(tr -d "\r" < "DIR/.env"); set +a; fi' \
    'if [ -z "${OPENAI_API_KEY:-}" ] && [ -r "DIR/openai_api_key" ]; then export OPENAI_API_KEY="$(tr -d "[:space:]" < "DIR/openai_api_key")"; fi'
  do
    line="${line//DIR/$dir}"
    grep -Fqx "$line" "$HOME/.bashrc" || printf '\n%s\n' "$line" >> "$HOME/.bashrc"
  done

  # env vars for notebook kernels: IPython startup file, loaded at every kernel start
  mkdir -p "$HOME/.ipython/profile_default/startup"
  cat > "$HOME/.ipython/profile_default/startup/00-load-env.py" <<EOF
import os
try:
    from dotenv import load_dotenv
    if os.path.exists("$dir/.env"):
        load_dotenv("$dir/.env")
    if "OPENAI_API_KEY" not in os.environ and os.path.exists("$dir/openai_api_key"):
        os.environ["OPENAI_API_KEY"] = open("$dir/openai_api_key").read().strip()
except Exception:
    pass
EOF

  # clone (or update) the private repo into a folder named after the repo
  tok=$(tr -d '[:space:]' < "$dir/code_token")
  url=$(tr -d '[:space:]' < "$dir/code_repo")
  name="${url%/}"; name="${name##*/}"; name="${name%.git}"; name="${name//[^A-Za-z0-9._-]/_}"
  dest="$root/${name:-private-code}"
  helper='!f() { echo username=x-access-token; echo password=$CODE_TOKEN; }; f'
  if [ -d "$dest/.git" ]; then
    CODE_TOKEN="$tok" git -C "$dest" -c credential.helper="$helper" pull --ff-only >> "$LOG" 2>&1 \
      && _sp_log "pull ok ($dest)" || _sp_log "pull FAILED ($dest)"
  else
    CODE_TOKEN="$tok" git -c credential.helper="$helper" clone --depth 1 "$url" "$dest" >> "$LOG" 2>&1 \
      && _sp_log "clone ok ($dest)" || _sp_log "clone FAILED ($dest)"
  fi

  # .env into the repo root for load_dotenv(), kept out of git
  if [ -d "$dest/.git" ] && [ -r "$dir/.env" ]; then
    cp "$dir/.env" "$dest/.env" && chmod 600 "$dest/.env" && _sp_log ".env copied to $dest"
    grep -qx '.env' "$dest/.git/info/exclude" 2>/dev/null || echo '.env' >> "$dest/.git/info/exclude"
  fi

  # install the private package (editable) into the session venv with uv
  if [ -f "$dest/pyproject.toml" ]; then
    if ! command -v uv >/dev/null; then
      _sp_log "uv not found, skipping package install"
    else
      py="$venv/bin/python"
      for i in $(seq 1 30); do [ -x "$py" ] && break; sleep 1; done
      [ -x "$py" ] && uvargs=(--python "$py")
      uv pip install "${uvargs[@]}" -e "$dest" >> "$LOG" 2>&1 \
        && _sp_log "uv install ok (python=${py})" || _sp_log "uv install FAILED"
    fi
  fi
}
_sp_main
unset -f _sp_main _sp_log