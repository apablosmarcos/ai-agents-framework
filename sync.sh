#!/usr/bin/env bash
# sync.sh — parte del framework ai-agents-framework
# Lee los metadatos YAML (scope + trigger) de cada skill y reescribe
# los bloques SYNC:START/END en TODOS los agents.md del proyecto.
#
# Lógica de routing por scope:
#   - Si existe un agents.md en una subcarpeta cuyo nombre contiene el scope → inyecta ahí
#   - En caso contrario → inyecta en el agents.md raíz (fallback)
#
# Idempotente: ejecutarlo varias veces produce el mismo resultado.
set -euo pipefail

# Autodetección: si este script vive dentro de core/, AGENTS_DIR es el padre
CORE_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(basename "$CORE_DIR")" == "core" ]]; then
  AGENTS_DIR="$(dirname "$CORE_DIR")"
else
  AGENTS_DIR="$CORE_DIR"
fi

PROJECT_ROOT="$(cd "$AGENTS_DIR/.." && pwd)"
ROOT_AGENTS_MD="$AGENTS_DIR/agents.md"
SEP=$'\x1F'   # ASCII Unit Separator — evita colisiones con | en los triggers

# ── 1. Descubrir todos los agents.md del proyecto ───────────────────────────

declare -a all_agents_files=()
while IFS= read -r -d '' f; do
  all_agents_files+=("$f")
done < <(find "$PROJECT_ROOT" -name "agents.md" -not -path "*/.git/*" -not -path "*/.agents/core/*" -print0 | sort -z)

# ── 2. Recopilar triggers agrupados por scope ────────────────────────────────
# Busca skills tanto en .agents/skills/ (dominio) como en core/skills/ (framework)

declare -A scope_triggers   # scope → triggers separados por SEP

# Función para procesar skills de un directorio
process_skills_dir() {
  local skills_dir="$1"
  [[ -d "$skills_dir" ]] || return 0

  while IFS= read -r -d '' skill_file; do
    # Saltar meta-skills
    [[ "$skill_file" == */meta/* ]] && continue

    # Extraer bloque frontmatter (entre los dos primeros ---)
    frontmatter=""
    in_front=0
    found_open=0
    while IFS= read -r line; do
      if [[ "$line" == "---" ]]; then
        if [[ $found_open -eq 0 ]]; then
          found_open=1
          in_front=1
          continue
        else
          break
        fi
      fi
      [[ $in_front -eq 1 ]] && frontmatter+="$line"$'\n'
    done < "$skill_file"

    [[ -z "$frontmatter" ]] && continue

    # Parsear scope y trigger del frontmatter
    scope=""
    trigger=""
    # Ruta relativa desde skills/ (ej: nodejs-backend-patterns/SKILL)
    skill_name="${skill_file#$skills_dir/}"
    skill_name="${skill_name%.md}"

    while IFS= read -r line; do
      if [[ "$line" =~ ^scope:[[:space:]]*(.+)$ ]]; then
        scope="${BASH_REMATCH[1]}"
        scope="${scope//\"/}" ; scope="${scope//\'/}" ; scope="${scope// /}"
      fi
      if [[ "$line" =~ ^trigger:[[:space:]]*(.+)$ ]]; then
        trigger="${BASH_REMATCH[1]}"
        trigger="${trigger#\"}" ; trigger="${trigger%\"}"
        trigger="${trigger#\'}" ; trigger="${trigger%\'}"
      fi
    done <<< "$frontmatter"

    # Avisar si falta scope o trigger — skill incompleta
    if [[ -z "$scope" && -z "$trigger" ]]; then
      echo "  ⚠ SKIP  $(basename "$skill_file") — sin scope ni trigger en el frontmatter"
      continue
    elif [[ -z "$scope" ]]; then
      echo "  ⚠ SKIP  $(basename "$skill_file") — frontmatter sin 'scope:' definido"
      continue
    elif [[ -z "$trigger" ]]; then
      echo "  ⚠ SKIP  $(basename "$skill_file") — frontmatter sin 'trigger:' definido"
      continue
    fi

    entry="- Activa \`skills/${skill_name}.md\` ${trigger}"

    if [[ -n "${scope_triggers[$scope]+_}" ]]; then
      scope_triggers[$scope]+="${SEP}${entry}"
    else
      scope_triggers[$scope]="${entry}"
    fi

  done < <(find "$skills_dir" -name "*.md" -not -path "*/meta/*" -print0 | sort -z)
}

# Procesar skills de dominio del proyecto
process_skills_dir "$AGENTS_DIR/skills"

# Procesar skills del framework (core/skills/)
process_skills_dir "$CORE_DIR/skills"

# ── 3. Para cada scope, elegir el agents.md de destino ──────────────────────

# Devuelve la ruta del agents.md más adecuado para un scope dado.
# Criterio: si algún agents.md (no el raíz) está en una ruta que contiene
# el scope como segmento de directorio, se usa ese. Si no, el raíz.
pick_agents_md() {
  local scope="$1"

  # scope: root → siempre agents.md raíz, sin buscar subcarpetas
  if [[ "$scope" == "root" ]]; then
    echo "$ROOT_AGENTS_MD"
    return
  fi

  for f in "${all_agents_files[@]}"; do
    [[ "$f" == "$ROOT_AGENTS_MD" ]] && continue
    # Comparar el directorio padre contra el scope
    local dir
    dir="$(dirname "$f")"
    local basename_dir
    basename_dir="$(basename "$dir")"
    if [[ "$basename_dir" == *"$scope"* ]]; then
      echo "$f"
      return
    fi
  done

  # Fallback: agents.md raíz
  echo "$ROOT_AGENTS_MD"
}

# ── 4. Reescribir bloques SYNC en el agents.md correspondiente ───────────────

rewrite_sync_block() {
  local target_file="$1"
  local scope="$2"
  local new_block="$3"

  local file_content
  file_content="$(cat "$target_file")"

  if echo "$file_content" | grep -q "SYNC:START scope=${scope} "; then
    # El bloque ya existe → reemplazar
    file_content="$(awk -v scope="$scope" -v new_block="$new_block" '
      BEGIN { in_block=0 }
      /<!-- SYNC:START scope=/ {
        if ($0 ~ "scope=" scope " ") { in_block=1; next }
      }
      /<!-- SYNC:END scope=/ {
        if (in_block) {
          in_block=0
          print new_block
          next
        }
      }
      !in_block { print }
    ' <<< "$file_content")"
  else
    # Bloque nuevo → insertar después del último <!-- SYNC:END ... --> existente
    # Si no existe ningún bloque SYNC previo, insertar al final del fichero.
    file_content="$(awk -v new_block="$new_block" '
      /<!-- SYNC:END scope=/ { last_sync_end=NR; last_sync_line=$0 }
      { lines[NR]=$0 }
      END {
        if (NR == 0) {
          print new_block
          next
        }
        if (last_sync_end == 0) {
          for (i=1; i<=NR; i++) {
            print lines[i]
          }
          print ""
          print new_block
          next
        }
        for (i=1; i<=NR; i++) {
          print lines[i]
          if (i==last_sync_end) {
            print ""
            print new_block
          }
        }
      }
    ' <<< "$file_content")"
    echo "  ✚ bloque SYNC nuevo insertado: scope=${scope}"
  fi

  printf '%s\n' "$file_content" > "$target_file"
}

for scope in "${!scope_triggers[@]}"; do
  target="$(pick_agents_md "$scope")"

  # Construir bloque nuevo
  new_block="<!-- SYNC:START scope=${scope} -->"$'\n'
  IFS="$SEP" read -ra entries <<< "${scope_triggers[$scope]}"
  for entry in "${entries[@]}"; do
    new_block+="${entry}"$'\n'
  done
  new_block+="<!-- SYNC:END scope=${scope} -->"

  rewrite_sync_block "$target" "$scope" "$new_block"

  # Mostrar destino relativo al proyecto
  rel_target="${target#$PROJECT_ROOT/}"
  echo "  ✓ scope=${scope} → ${rel_target}"
done

# ── 5. Limpiar bloques SYNC zombie (scopes sin skills activas) ───────────────
# Si un bloque SYNC:START scope=X existe en agents.md pero no hay ninguna skill
# con ese scope, el bloque queda obsoleto. Se elimina por completo.

for agents_file in "${all_agents_files[@]}"; do
  # Extraer todos los scopes presentes en este agents.md
  existing_scopes=()
  while IFS= read -r line; do
    if [[ "$line" =~ \<\!--\ SYNC:START\ scope=([^\ ]+)\ --\> ]]; then
      existing_scopes+=("${BASH_REMATCH[1]}")
    fi
  done < "$agents_file"

  for existing_scope in "${existing_scopes[@]}"; do
    # Si el scope ya tiene skills activas, ya fue reescrito arriba — omitir
    [[ -n "${scope_triggers[$existing_scope]+_}" ]] && continue

    # Sin skills activas → eliminar el bloque completo
    file_content="$(cat "$agents_file")"
    file_content="$(awk -v scope="$existing_scope" '
      BEGIN { in_block=0; found_end=0 }
      /<!-- SYNC:START scope=/ {
        if ($0 ~ "scope=" scope " ") { in_block=1; next }
      }
      /<!-- SYNC:END scope=/ {
        if (in_block) { in_block=0; found_end=1; next }
      }
      !in_block { print }
      END {
        if (in_block) {
          print "ERROR: bloque SYNC:START scope=" scope " sin cierre SYNC:END" > "/dev/stderr"
          exit 1
        }
      }
    ' <<< "$file_content")"
    awk_exit=$?
    if [[ $awk_exit -ne 0 ]]; then
      rel_file="${agents_file#$PROJECT_ROOT/}"
      echo "  ⚠ SKIP zombie scope=${existing_scope}: bloque sin cierre END — corrige manualmente en ${rel_file}"
      continue
    fi
    printf '%s\n' "$file_content" > "$agents_file"

    rel_file="${agents_file#$PROJECT_ROOT/}"
    echo "  🗑 bloque zombie eliminado: scope=${existing_scope} en ${rel_file}"
  done
done

echo "✓ sync.sh completado — ${#scope_triggers[@]} scope(s) procesados"
