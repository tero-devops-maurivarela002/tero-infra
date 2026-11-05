# Uso de IA

La letra del obligatorio pide declarar las herramientas de IA usadas y el contexto en que se usaron. Este documento resume cómo se usó la IA en el proyecto.

## Herramienta

**Claude** (Anthropic), a través de Claude Code y de un proyecto de Claude.

## Cómo se usó

Claude se usó como **apoyo y tutor** durante todo el proyecto:

- **Tutor y guía:** explica qué pide cada tarea de la letra, por qué, y en qué orden conviene hacerla.
- **Consultas y dudas:** respuestas puntuales sobre herramientas (Docker, GitHub, rulesets, etc.) y diagnóstico de errores.
- **Correcciones y revisión:** el autor propone las soluciones y Claude las revisa, indicando si falta algún paso o si hay algo que mejorar.
- **Documentos:** ayuda a armar y redactar los documentos en Markdown (por ejemplo el assessment, los ADR y este registro), que el autor revisa y ajusta.

Claude trabaja con instrucciones de actuar como tutor: el autor realiza los cambios en los repositorios, en GitHub y en Jira, y Claude lo encamina.

## Criterios del autor

- La IA propone y explica; **el autor decide, ejecuta y puede justificar cada cambio**.
- Lo generado se contrasta con la letra del obligatorio y con una prueba real (comando, captura o resultado del pipeline).
- La IA puede equivocarse. Cuando pasa, se corrige y se documenta qué ocurrió.
