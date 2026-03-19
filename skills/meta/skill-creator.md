---
scope: meta
tools:
  - read
  - write
  - bash
trigger: "cuando alguien pida crear una nueva skill"
alwaysApply: false
---

# Skill: Crear una Nueva Skill

> **Trigger:** Lee este archivo ANTES de crear cualquier nueva skill en `.agents/skills/`.

---

## Scopes Disponibles

| Scope | Cuándo usarlo |
|-------|---------------|
| `root` | Skills genéricas transversales al proyecto: flujos de trabajo del equipo (commits, PRs, reviews…). `sync.sh` las inyecta siempre en el `agents.md` raíz. |
| `meta` | Skills sobre el propio sistema de orquestación |
| *(personalizado)* | Define scopes propios según el dominio de tu proyecto |

### Sobre el scope `root` — Skills Genéricas

Las skills con `scope: root` no son de dominio técnico sino de **proceso de equipo**. Ejemplos típicos:
- `commits.md` — convención de mensajes de commit (Conventional Commits, formato propio…)
- `pr.md` — plantilla exacta para describir Pull Requests

Se crean igual que cualquier skill (en `.agents/skills/`) pero `sync.sh` las trata diferente:
siempre van al `agents.md` raíz, nunca a sub-agents.md de subcarpetas, porque son reglas
que aplican a todo el proyecto sin excepción.

**Cuando el usuario proporcione estas skills**, créalas con `scope: root` y ejecuta `bash setup.sh`.

---

## Estructura Obligatoria de una Skill

Cada skill **debe** comenzar con el bloque frontmatter YAML seguido del contenido:

```markdown
---
scope: <scope>
tools:
  - read
  - write
  - grep
  - glob
  - bash        # Solo si necesita ejecutar comandos
trigger: "cuando vayas a ..."
alwaysApply: false
---

# Skill: Nombre Descriptivo

> **Trigger:** Lee este archivo ANTES de ...

---

## Metadatos

- **Dominio:** `ruta/al/dominio/`
- **Patrón:** Descripción del patrón arquitectónico

---

## Reglas Obligatorias

1. Regla clara y accionable
2. ...

---

## Template: [Componente Principal]

\`\`\`javascript
// código de ejemplo
\`\`\`

---

## Checklist antes de hacer commit

- [ ] Item verificable
- [ ] ...

---

## Resources

### Documentación oficial
- [Enlace a doc oficial relevante]()

### Ejemplos reales en este proyecto
- Fichero de referencia: \`ruta/al/fichero/real.js\`
```

---

## Pasos Post-Creación (OBLIGATORIOS)

Después de crear o modificar cualquier skill, ejecutar siempre en este orden:

**Paso 1 — Actualizar el índice de `project.md` manualmente**

Añadir una fila a la tabla "Índice de Skills" en `.agents/project.md`:

```markdown
| Descripción de cuándo usarla | [`skills/nombre-skill.md`](skills/nombre-skill.md) |
```

**Paso 2 — Sincronizar y propagar**

```bash
# Reescribe los bloques SYNC con el nuevo trigger
bash .agents/core/sync.sh

# Propaga symlinks a todas las IAs y regenera copilot-instructions.md
bash setup.sh
```

**Paso 3 — Verificar**
- El nuevo symlink aparece en `.claude/commands/`
- El nuevo symlink aparece en `.cursor/rules/` (si no es meta)
- `.github/copilot-instructions.md` contiene el contenido de la nueva skill (si no es meta)
- La nueva fila aparece en el índice de `project.md`

**Nota sobre `skills-lock.json`:** Si la skill proviene de `npx skills add`, se actualiza automáticamente `skills-lock.json` en la raíz del proyecto. Este fichero **debe commitarse** junto con la skill (es el equivalente a `package-lock.json` para el sistema de orquestación). Si está en estado `untracked`, añádelo con `git add skills-lock.json` antes del commit.

---

## Reglas de Nomenclatura

- Nombre de archivo: `kebab-case.md` (ej: `nueva-entidad.md`)
- `scope`: siempre en minúsculas, sin espacios
- `trigger`: frase en español comenzando con "cuando vayas a..."
- Meta-skills van en `.agents/skills/meta/` — no se propagan a Cursor ni Copilot

### Skills externas o descargadas

El sistema acepta skills en cualquier idioma. Una skill descargada de una fuente externa puede estar en inglés u otro idioma — no es necesario traducirla. Lo único obligatorio es que el frontmatter tenga `scope` y `trigger` válidos para que `sync.sh` la procese correctamente. Si la skill externa no tiene `trigger` en español, añade uno manualmente en el frontmatter antes de ejecutar `setup.sh`.
