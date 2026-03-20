# ai-agents-framework

Framework reutilizable de orquestación de agentes IA para proyectos de software.
Define cómo debe comportarse un agente IA (Claude Code, Cursor, Copilot, Gemini…) cuando trabaja en un proyecto: qué leer primero, cómo tomar decisiones, cuándo preguntar, cómo estructurar el conocimiento del proyecto en **skills** y cómo mantenerlo todo sincronizado automáticamente.

---

## El problema que resuelve

Cuando un agente IA trabaja en un proyecto sin contexto estructurado, actúa a ciegas: no sabe qué patrones sigue el proyecto, qué convenciones tiene, qué no debe tocar o cómo debe responder. El resultado es código inconsistente, decisiones arbitrarias y mucho trabajo de corrección manual.

La solución habitual es escribir un fichero de instrucciones monolítico (un `CLAUDE.md` gigante, un `.cursorrules`…). Esto funciona en proyectos pequeños, pero no escala: las instrucciones se mezclan, es difícil mantenerlas actualizadas y son completamente específicas de un solo proyecto.

**`ai-agents-framework` resuelve esto con tres ideas:**

1. **Separa lo universal de lo específico.** El protocolo de comportamiento del agente (cómo razona, cómo delega, cómo escala) vive en este repo y se comparte entre proyectos. Las reglas concretas del proyecto (su arquitectura, sus convenciones, sus endpoints) viven en el propio proyecto.

2. **Skills modulares.** El conocimiento se divide en ficheros pequeños y enfocados llamados _skills_. Cada skill cubre un dominio concreto (controllers, errores, entidades…) y tiene metadatos que le dicen al agente cuándo debe leerla.

3. **Propagación automática.** Un único comando (`bash setup.sh`) regenera y distribuye todo el contexto a todos los agentes IA que uses: Claude Code, Cursor, Copilot y Gemini reciben exactamente la misma información, siempre actualizada.

---

## Arquitectura general

```
tu-proyecto/
├── .agents/
│   ├── core/                  ← este repo (git subtree, SOLO LECTURA)
│   │   ├── core.md            ← protocolo universal del orquestador
│   │   ├── sync.sh            ← motor de sincronización de skills
│   │   ├── install.sh         ← inicializador para proyectos nuevos
│   │   └── skills/meta/       ← skills sobre el propio sistema
│   │       ├── skill-creator.md
│   │       └── skill-sync.md
│   ├── project.md             ← reglas específicas de TU proyecto (editable)
│   ├── agents.md              ← GENERADO: core.md + project.md (no editar)
│   └── skills/                ← skills de dominio de TU proyecto
│       ├── mi-skill.md
│       └── ...
├── setup.sh                   ← propaga todo a todos los agentes
├── framework-sync.sh          ← actualiza el framework a la última versión
├── CLAUDE.md                  ← symlink → .agents/agents.md
├── GEMINI.md                  ← symlink → .agents/agents.md
├── .claude/commands/          ← symlinks a cada skill (para Claude Code)
├── .cursor/rules/             ← symlinks a skills de dominio (para Cursor)
└── .github/copilot-instructions.md  ← concatenación completa (para Copilot)
```

El fichero que lee cada agente IA es siempre `.agents/agents.md` — generado automáticamente concatenando `core.md` (universal) y `project.md` (específico del proyecto). Ningún agente lee ficheros del framework directamente.

---

## Ficheros del framework

### `core.md` — El protocolo universal

Es el "manual de comportamiento" del agente. Define tres cosas:

**1. Protocolo de orquestación con subagentes**

Cuando el agente necesita delegar trabajo (leer un conjunto de ficheros, buscar usos de una función, explorar una subcarpeta), debe seguir reglas estrictas para no saturar su contexto:
- Los subagentes solo devuelven **resúmenes**, nunca el código completo.
- Solo el orquestador principal toma decisiones. El subagente reporta hechos.
- Cada subagente recibe **contexto mínimo**: solo lo que necesita para su tarea.

Esto es crítico para mantener la calidad del razonamiento del agente en tareas largas. Un agente que absorbe demasiado contexto empieza a cometer errores y a perder coherencia.

**2. Comportamiento del orquestador (persona)**

Define cómo debe actuar el agente, independientemente del proyecto:
- **Lee primero, escribe después.** Nunca modificar ficheros sin haberlos leído.
- **Presenta un plan antes de actuar** en tareas no triviales y espera confirmación.
- **Hace preguntas aclaratorias** cuando el enunciado es ambiguo.
- **Explica el razonamiento** de cada decisión de diseño.
- **Alerta de riesgos** antes de cambios que afecten contratos existentes.

**3. Estrategia de escalado**

Cuándo crear un `agents.md` específico en una subcarpeta del proyecto (para equipos o módulos con reglas muy distintas al raíz). Incluye la invariante: las reglas globales siempre están solo en el `agents.md` raíz, nunca se copian en los sub-agents.

---

### `sync.sh` — El motor de sincronización

Es el script más complejo del framework. Su función es mantener la sección "Reglas de Autoinvocación" de `agents.md` siempre sincronizada con las skills reales del proyecto, sin intervención manual.

**Cómo funciona:**

Cada skill tiene un bloque frontmatter YAML al inicio:

```markdown
---
scope: api
trigger: "cuando vayas a crear o modificar controllers, services, utils o routes"
---
```

`sync.sh` lee ese frontmatter de todas las skills y genera automáticamente en `agents.md` los bloques de activación:

```markdown
<!-- SYNC:START scope=api -->
- Activa `skills/api-node.md` cuando vayas a crear o modificar controllers...
<!-- SYNC:END scope=api -->
```

**Qué hace exactamente `sync.sh`:**

1. **Descubre todos los `agents.md`** del proyecto (raíz y subcarpetas), excluyendo `core/`.
2. **Lee el frontmatter** de cada skill en `.agents/skills/` y en `core/skills/`.
3. **Agrupa los triggers por `scope`**: todas las skills con el mismo scope van al mismo bloque.
4. **Enruta cada scope** al `agents.md` correcto: si existe un `agents.md` en una subcarpeta cuyo nombre contiene el scope, lo inyecta ahí. Si no, usa el `agents.md` raíz como fallback. El scope `root` siempre va al raíz.
5. **Reescribe los bloques `SYNC:START/END`** en el fichero destino. Si el bloque ya existe, lo reemplaza. Si no existe, lo inserta después del último bloque SYNC existente.
6. **Limpia bloques zombie**: si un bloque `SYNC:START scope=X` existe en `agents.md` pero ya no hay ninguna skill con ese scope (porque se eliminó), el bloque se borra automáticamente.

**Es completamente idempotente**: ejecutarlo diez veces seguidas produce exactamente el mismo resultado.

**Autodetección de ubicación**: el script detecta si está dentro de `core/` o en la raíz de `.agents/` y ajusta las rutas automáticamente. Esto permite que funcione igual desde `.agents/core/sync.sh` (caso normal) o desde `.agents/sync.sh` (standalone).

---

### `install.sh` — El inicializador

Bootstrapea el framework en un proyecto nuevo. Se ejecuta una sola vez después de añadir el subtree. Hace exactamente esto:

1. **Crea `.agents/project.md`** con una plantilla con marcadores `[...]` que el desarrollador rellena. Si ya existe, no lo sobreescribe.
2. **Crea `setup.sh`** en la raíz del proyecto (desde una plantilla completa y funcional). Si ya existe, no lo sobreescribe.
3. **Crea `framework-sync.sh`** en la raíz del proyecto. Si ya existe, no lo sobreescribe.
4. **Actualiza `.gitignore`** añadiendo las entradas necesarias (`CLAUDE.md`, `GEMINI.md`, `.agents/agents.md`, etc.) solo si no están ya presentes.
5. **Crea `.agents/skills/`** si no existe.
6. **Imprime instrucciones** de qué hay que hacer manualmente a continuación.

---

### `skills/meta/skill-creator.md` — Cómo crear una skill nueva

Instrucción para el agente IA sobre cómo crear correctamente una skill nueva. Cubre:

- Los **scopes disponibles** y cuándo usar cada uno (incluyendo `root` para skills genéricas de equipo como convenciones de commits o plantillas de PR).
- La **estructura obligatoria** de una skill: frontmatter YAML (`scope`, `trigger`, `tools`, `alwaysApply`) seguido del contenido en Markdown.
- Los **pasos post-creación**: actualizar el índice en `project.md`, ejecutar `sync.sh` y `setup.sh`, y verificar que los symlinks se han generado correctamente.
- **Reglas de nomenclatura**: `kebab-case.md`, `scope` en minúsculas, `trigger` en español empezando por "cuando vayas a…"
- Cómo manejar **skills externas o en otros idiomas**: no es necesario traducirlas, solo asegurarse de que el frontmatter tiene `scope` y `trigger` válidos.

---

### `skills/meta/skill-sync.md` — Cómo sincronizar tras modificar una skill

Instrucción para el agente IA sobre cuándo y cómo ejecutar los scripts de sincronización. Clarifica:

- Cuándo hace falta ejecutar `sync.sh` (solo si cambia el frontmatter: `scope` o `trigger`).
- Cuándo hace falta ejecutar solo `setup.sh` (si cambia el contenido interno de la skill).
- El **procedimiento completo en 4 pasos**: actualizar el índice en `project.md`, ejecutar `sync.sh`, ejecutar `setup.sh`, verificar.
- **Qué NO hace `sync.sh`**: no toca las reglas globales de `project.md`, no modifica el contenido interno de las skills, no propaga meta-skills a Cursor ni Copilot, no hace commit.
- La **idempotencia** de ambos scripts.

---

## Cómo se usa en un proyecto

### Instalación inicial

```bash
# 1. Desde la raíz del proyecto (con git ya inicializado):
git subtree add \
  --prefix=.agents/core \
  https://github.com/apablosmarcos/ai-agents-framework.git \
  main \
  --squash

# 2. Ejecutar el instalador
bash .agents/core/install.sh

# 3. Rellenar .agents/project.md con las reglas del proyecto

# 4. Crear skills de dominio en .agents/skills/
# Ejemplo: .agents/skills/android-architecture.md

# 5. Propagar todo
bash setup.sh
```

### Uso diario

**Añadir una skill nueva:**
```bash
# Crear el fichero en .agents/skills/
# Ejecutar:
bash setup.sh
```

**Actualizar el framework a la última versión:**
```bash
bash framework-sync.sh
```

**Regenerar todo** (tras editar `project.md` o cualquier skill):
```bash
bash setup.sh
```

---

## El sistema de skills

Una skill es un fichero Markdown con **frontmatter YAML** que describe cuándo debe activarse:

```markdown
---
scope: api
tools:
  - read
  - write
  - grep
trigger: "cuando vayas a crear o modificar controllers, services o utils"
alwaysApply: false
---

# Skill: Nombre de la Skill

Contenido con las reglas, patrones, ejemplos y checklists del dominio.
```

### Campos del frontmatter

| Campo | Descripción |
|-------|-------------|
| `scope` | Agrupa skills relacionadas. Determina en qué `agents.md` se inyecta el trigger. El scope `root` siempre va al raíz. |
| `trigger` | Frase que describe cuándo el agente debe leer esta skill. `sync.sh` la extrae y la inyecta en `agents.md` automáticamente. |
| `tools` | Herramientas que el agente puede usar cuando aplica esta skill. |
| `alwaysApply` | Si `true`, el agente siempre carga la skill independientemente del contexto. |

### Tipos de skills

| Tipo | Ubicación | Propagación |
|------|-----------|-------------|
| **Dominio** | `.agents/skills/` | Claude, Cursor, Copilot, Gemini |
| **Meta** | `.agents/skills/meta/` | Solo Claude (instrucciones para el sistema) |
| **Framework** | `.agents/core/skills/meta/` | Solo Claude (vienen con el framework) |

### Scopes predefinidos

| Scope | Comportamiento |
|-------|---------------|
| `root` | Siempre va al `agents.md` raíz, independientemente de sub-agents.md |
| `meta` | Skills sobre el sistema de orquestación, no sobre el código |
| Cualquier otro | Se enruta al `agents.md` de la subcarpeta cuyo nombre contenga el scope. Si no existe esa subcarpeta, va al raíz. |

---

## Qué se commitea en cada repo

| Fichero | Este repo (framework) | Tu proyecto |
|---------|----------------------|-------------|
| `core.md`, `sync.sh`, `install.sh` | ✅ | vía subtree |
| `skills/meta/` | ✅ | vía subtree |
| `.agents/core/` | — | ✅ (es el subtree) |
| `.agents/project.md` | — | ✅ |
| `.agents/skills/` (dominio) | — | ✅ |
| `setup.sh`, `framework-sync.sh` | — | ✅ |
| `.agents/agents.md` | — | ❌ generado |
| `CLAUDE.md`, `GEMINI.md` | — | ❌ generados |
| `.claude/commands/`, `.cursor/rules/` | — | ❌ generados |
| `.github/copilot-instructions.md` | — | ❌ generado |

---

## Compatibilidad con agentes IA

| Agente | Cómo recibe el contexto |
|--------|------------------------|
| **Claude Code** | `CLAUDE.md` (symlink a `agents.md`) + skills en `.claude/commands/` |
| **Cursor** | Skills de dominio en `.cursor/rules/` (sin meta-skills) |
| **GitHub Copilot** | `.github/copilot-instructions.md` (concatenación de agents.md + todas las skills) |
| **Gemini CLI** | `GEMINI.md` (symlink a `agents.md`) |

---

## Requisitos

- **Bash 4+** (macOS usa Bash 3 por defecto — instalar con `brew install bash`)
- **Git 2.20+** (para `git subtree`)
- **awk** y **find** (disponibles en cualquier sistema Unix)
