---
scope: meta
tools:
  - bash
  - read
trigger: "cuando hayas creado, modificado o eliminado una skill"
alwaysApply: false
---

# Skill: Sincronizar el Sistema de Orquestación

> **Trigger:** Lee este archivo DESPUÉS de crear o modificar cualquier skill.

---

## Cuándo Ejecutar

Ejecutar `sync.sh` + `setup.sh` siempre que:

- Crees una skill nueva en `.agents/skills/`
- Modifiques el `trigger` o `scope` de una skill existente
- Elimines una skill
- Modifiques `.agents/project.md` manualmente en la sección de reglas globales

Si solo cambias el contenido interno de una skill (templates, ejemplos, checklists)
sin tocar el frontmatter:

- `sync.sh`: **no es necesario**
- `setup.sh`: **sí es necesario** para propagar cambios a `.cursor/rules/`,
  `.claude/commands/` y regenerar `.github/copilot-instructions.md`

---

## Procedimiento (4 pasos)

### Paso 1 — Actualizar el índice de `project.md` si es necesario

- Si **creaste** una skill → añade su fila en la tabla "Índice de Skills" de `.agents/project.md`
- Si **borraste** una skill → elimina su fila del índice
- Si **renombraste** una skill → actualiza la fila con la nueva ruta

### Paso 2 — Sincronizar `agents.md`

```bash
bash .agents/core/sync.sh
```

Reescribe los bloques `<!-- SYNC:START/END -->` con los triggers actuales de todas las skills.

### Paso 3 — Propagar a todas las IAs

```bash
bash setup.sh
```

Actualiza symlinks en `.claude/commands/`, `.cursor/rules/` (elimina huérfanos automáticamente),
regenera `.github/copilot-instructions.md` y crea/actualiza `GEMINI.md`.

### Paso 4 — Verificar

```bash
# Comprobar que los bloques SYNC están actualizados
grep -A 5 "SYNC:START" .agents/agents.md

# Comprobar symlinks de Claude Code
ls -la .claude/commands/

# Comprobar symlinks de Cursor
ls -la .cursor/rules/

# Comprobar Copilot (debe incluir el contenido de la skill nueva/modificada)
grep -c "nombre-de-tu-skill" .github/copilot-instructions.md
```

---

## Qué NO hace `sync.sh`

- **No modifica** las reglas globales de `project.md` (arquitectura, nomenclatura…)
- **No toca** el contenido interno de las skills
- **No propaga** meta-skills a Cursor ni a Copilot (solo a `.claude/commands/`)
- **No hace commit** — eso es responsabilidad del desarrollador

---

## Idempotencia

Ambos scripts son idempotentes: ejecutarlos varias veces produce el mismo resultado.
Si algo falla, revisar que los archivos de skills tengan frontmatter YAML válido
(bloque delimitado por `---` al inicio del archivo).
