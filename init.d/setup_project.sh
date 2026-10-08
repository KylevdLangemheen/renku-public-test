#!/bin/bash
# init.d/setup_project.sh: public file, contains no secrets. Never blocks session start.
_sp_main() {
  local LOG="$HOME/setup_project.log" root="${RENKU_WORKING_DIR:-/home/renku/work}" dir="${CODE_ACCESS_DIR:-}"
  local i f line tok url dest helper venv py
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

  # OpenAI key for terminals: read at shell start, value never stored
  line='if [ -z "${OPENAI_API_KEY:-}" ] && [ -r "DIR/openai_api_key" ]; then export OPENAI_API_KEY="$(tr -d "[:space:]" < "DIR/openai_api_key")"; fi'
  line="${line//DIR/$dir}"
  touch "$HOME/.bashrc"
  grep -Fqx "$line" "$HOME/.bashrc" || printf '\n%s\n' "$line" >> "$HOME/.bashrc"

  # clone (or update) the private repo
  tok=$(tr -d '[:space:]' < "$dir/code_token")
  url=$(tr -d '[:space:]' < "$dir/code_repo")
  dest="$root/private-code"
  helper='!f() { echo username=x-access-token; echo password=$CODE_TOKEN; }; f'
  if [ -d "$dest/.git" ]; then
    CODE_TOKEN="$tok" git -C "$dest" -c credential.helper="$helper" pull --ff-only >> "$LOG" 2>&1 \
      && _sp_log "pull ok" || _sp_log "pull FAILED"
  else
    CODE_TOKEN="$tok" git -c credential.helper="$helper" clone --depth 1 "$url" "$dest" >> "$LOG" 2>&1 \
      && _sp_log "clone ok" || _sp_log "clone FAILED"
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