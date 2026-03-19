#!/usr/bin/env bash
# install.sh — Inicializa el framework ai-agents-framework en un proyecto nuevo.
# Ejecutar desde la raíz del proyecto después de añadir el subtree en .agents/core/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="$PROJECT_ROOT/.agents"
CORE_DIR="$AGENTS_DIR/core"

echo "=== ai-agents-framework install.sh ==="
echo "Proyecto raíz: $PROJECT_ROOT"
echo ""

# ── 1. Crear .agents/project.md si no existe ────────────────────────────────

if [[ -f "$AGENTS_DIR/project.md" ]]; then
  echo "  ⏭  .agents/project.md ya existe — no se sobreescribe"
else
  cat > "$AGENTS_DIR/project.md" << 'TEMPLATE'
# Orquestador — [NOMBRE DEL PROYECTO]

## Visión General del Proyecto

[DESCRIPCIÓN BREVE]

**Stack principal:** [TECNOLOGÍAS]

---

## Estructura del Repositorio

[ÁRBOL DEL PROYECTO]

---

## Índice de Skills — ¿Cuándo usar cada una?

| Si la tarea involucra... | Lee esta skill primero |
|--------------------------|------------------------|
| Crear una nueva skill | `skills/meta/skill-creator.md` |

---

## Reglas de Autoinvocación

<!-- SYNC:START y SYNC:END son gestionados por sync.sh automáticamente -->

---

## Reglas Globales del Proyecto

[CONVENCIONES DE NOMENCLATURA, ARQUITECTURA, ETC.]
TEMPLATE
  echo "  ✓ .agents/project.md creado (rellena los marcadores [...])"
fi

# ── 2. Crear setup.sh en raíz si no existe ───────────────────────────────────

if [[ -f "$PROJECT_ROOT/setup.sh" ]]; then
  echo "  ⏭  setup.sh ya existe — no se sobreescribe"
else
  cat > "$PROJECT_ROOT/setup.sh" << 'SETUP_TEMPLATE'
#!/usr/bin/env bash
# setup.sh — Propaga las skills de .agents/ a todas las IAs compatibles.
# Idempotente: usa ln -sf y mkdir -p en todas las operaciones.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$ROOT/.agents"
CORE_DIR="$AGENTS_DIR/core"
PROJECT_MD="$AGENTS_DIR/project.md"
SKILLS_DIR="$AGENTS_DIR/skills"

echo "=== setup.sh — Propagando skills a todas las IAs ==="

# ── Paso 0: Generar .agents/agents.md ────────────────────────────────────────
echo ""
echo "→ Generando .agents/agents.md"
{ cat "$CORE_DIR/core.md"; echo ""; echo "---"; echo ""; cat "$PROJECT_MD"; } > "$AGENTS_DIR/agents.md"
echo "  ✓ .agents/agents.md generado"

# ── Claude Code ───────────────────────────────────────────────────────────────
echo ""
echo "→ Claude Code (.claude/ y .claude/commands/)"

mkdir -p "$ROOT/.claude/commands"

[[ -d "$ROOT/.claude/skills" ]] && rm -rf "$ROOT/.claude/skills" && echo "  ✓ .claude/skills/ eliminado (artefacto del instalador)"

while IFS= read -r -d '' link; do
  [ -e "$link" ] || { rm "$link"; echo "  🗑 huérfano eliminado: $(basename "$link")"; }
done < <(find "$ROOT/.claude/commands" -type l -print0 2>/dev/null)

ln -sf "$AGENTS_DIR/agents.md" "$ROOT/CLAUDE.md"
echo "  ✓ CLAUDE.md → .agents/agents.md"

while IFS= read -r -d '' skill; do
  skill_rel="${skill#$SKILLS_DIR/}"
  [[ "$skill_rel" == "$skill" ]] && skill_rel="${skill#$CORE_DIR/skills/}"
  link_name="${skill_rel//\//-}"
  ln -sf "$skill" "$ROOT/.claude/commands/$link_name"
  echo "  ✓ .claude/commands/$link_name"
done < <(find "$AGENTS_DIR/skills" "$CORE_DIR/skills" -name "*.md" -print0 2>/dev/null | sort -z)

# ── Cursor ────────────────────────────────────────────────────────────────────
echo ""
echo "→ Cursor (.cursor/rules/)"

mkdir -p "$ROOT/.cursor/rules"

while IFS= read -r -d '' link; do
  [ -e "$link" ] || { rm "$link"; echo "  🗑 huérfano eliminado: $(basename "$link")"; }
done < <(find "$ROOT/.cursor/rules" -type l -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  rm "$f"
  echo "  🗑 fichero regular eliminado: $(basename "$f")"
done < <(find "$ROOT/.cursor/rules" -maxdepth 1 -type f -print0 2>/dev/null)

while IFS= read -r -d '' skill; do
  skill_rel="${skill#$SKILLS_DIR/}"
  [[ "$skill_rel" == "$skill" ]] && skill_rel="${skill#$CORE_DIR/skills/}"
  link_name="${skill_rel//\//-}"
  ln -sf "$skill" "$ROOT/.cursor/rules/$link_name"
  echo "  ✓ .cursor/rules/$link_name"
done < <(find "$AGENTS_DIR/skills" "$CORE_DIR/skills" -name "*.md" -not -path "*/meta/*" -print0 2>/dev/null | sort -z)

# ── Gemini CLI ────────────────────────────────────────────────────────────────
echo ""
echo "→ Gemini CLI (GEMINI.md)"

ln -sf "$AGENTS_DIR/agents.md" "$ROOT/GEMINI.md"
echo "  ✓ GEMINI.md → .agents/agents.md"

# ── Sincronizar bloques SYNC en agents.md ─────────────────────────────────────
echo ""
echo "→ Ejecutando sync.sh..."
bash "$CORE_DIR/sync.sh"

# ── GitHub Copilot ────────────────────────────────────────────────────────────
echo ""
echo "→ GitHub Copilot (.github/copilot-instructions.md)"

mkdir -p "$ROOT/.github"
copilot_out="$ROOT/.github/copilot-instructions.md"

{
  cat "$AGENTS_DIR/agents.md"
  echo ""
  echo "---"
  echo ""
  while IFS= read -r -d '' skill; do
    echo ""
    cat "$skill"
    echo ""
    echo "---"
    echo ""
  done < <(find "$AGENTS_DIR/skills" "$CORE_DIR/skills" -name "*.md" -not -path "*/meta/*" -print0 2>/dev/null | sort -z)
} > "$copilot_out"

echo "  ✓ .github/copilot-instructions.md (generado)"

echo ""
echo "=== setup.sh completado ==="
SETUP_TEMPLATE
  chmod +x "$PROJECT_ROOT/setup.sh"
  echo "  ✓ setup.sh creado"
fi

# ── 3. Crear framework-sync.sh en raíz si no existe ─────────────────────────

if [[ -f "$PROJECT_ROOT/framework-sync.sh" ]]; then
  echo "  ⏭  framework-sync.sh ya existe — no se sobreescribe"
else
  cat > "$PROJECT_ROOT/framework-sync.sh" << 'SYNC_TEMPLATE'
#!/usr/bin/env bash
# framework-sync.sh — Actualiza ai-agents-framework a la última versión.
set -euo pipefail

FRAMEWORK_REPO="git@github.com:TU_USUARIO/ai-agents-framework.git"

echo "=== Actualizando ai-agents-framework ==="
git subtree pull --prefix=.agents/core "$FRAMEWORK_REPO" main --squash

echo "=== Regenerando y propagando ==="
bash setup.sh

echo "=== Listo ==="
SYNC_TEMPLATE
  chmod +x "$PROJECT_ROOT/framework-sync.sh"
  echo "  ✓ framework-sync.sh creado (actualiza TU_USUARIO con tu usuario de GitHub)"
fi

# ── 4. Añadir entradas a .gitignore si no están ─────────────────────────────

GITIGNORE="$PROJECT_ROOT/.gitignore"

add_gitignore_entry() {
  local entry="$1"
  if [[ ! -f "$GITIGNORE" ]] || ! grep -qF "$entry" "$GITIGNORE"; then
    echo "$entry" >> "$GITIGNORE"
    echo "  ✓ .gitignore: añadido '$entry'"
  else
    echo "  ⏭  .gitignore: '$entry' ya presente"
  fi
}

echo ""
echo "→ Actualizando .gitignore"
add_gitignore_entry "CLAUDE.md"
add_gitignore_entry "GEMINI.md"
add_gitignore_entry ".agents/agents.md"
add_gitignore_entry ".github/copilot-instructions.md"
add_gitignore_entry ".claude/commands/"
add_gitignore_entry ".cursor/rules/"

# ── 5. Crear directorio .agents/skills/ si no existe ────────────────────────

mkdir -p "$AGENTS_DIR/skills"
echo ""
echo "  ✓ .agents/skills/ listo para tus skills de dominio"

# ── 6. Instrucciones finales ─────────────────────────────────────────────────

echo ""
echo "=== Instalación completada ==="
echo ""
echo "Próximos pasos:"
echo "  1. Edita .agents/project.md — rellena los marcadores [...]"
echo "  2. Crea skills de dominio en .agents/skills/"
echo "  3. Ejecuta: bash setup.sh"
echo ""
echo "Para actualizar el framework en el futuro:"
echo "  bash framework-sync.sh"
