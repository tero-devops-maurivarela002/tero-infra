# ADR-001: Estrategia de branching

- **Estado:** Aceptado
- **Fecha:** 04/11/2026
- **Decisores:** Mauricio Varela
- **Tarea relacionada:** DEVOPS-17

## Contexto

Tero es una tienda en línea con 6 microservicios que hoy se despliega a mano con `docker compose`. La auditoría técnica observó que nadie puede decir con certeza qué versión del código está corriendo ni repetir un despliegue de la misma manera dos veces.

Condiciones que pesan en la decisión:

- **Tres ambientes obligatorios:** Dev, Test y Prod, con quality gates entre ellos. Ningún artefacto se promueve si no cumple los umbrales de calidad y seguridad.
- **Revisión obligatoria:** la letra exige que ninguna rama de feature se fusione a `main` o `develop` sin la aprobación de al menos un revisor distinto del autor. El proyecto lo desarrolla una sola persona, por lo que la revisión se hace desde una segunda cuenta de GitHub.
- **Equipo de una sola persona, nuevo en prácticas DevOps:** conviene un modelo explícito, donde cada rama tenga un propósito claro, y no uno que dependa de disciplina implícita.
- **Operabilidad posterior:** el personal de Tero tendrá que entender y mantener el flujo cuando termine la consultoría.
- **Plazo corto:** cinco semanas, con sprints de una semana.

## Decisión

Adoptamos **Git Flow simplificado**, con las siguientes ramas:

| Rama | Propósito | Sale de | Se fusiona a | Despliegue |
|---|---|---|---|---|
| `main` | Código en producción. Cada commit en `main` es una versión liberada. | n/a | n/a | Prod (con aprobación manual) |
| `develop` | Integración continua del trabajo en curso. | `main` | n/a | Dev (automático) |
| `feature/DEVOPS-XX-descripcion` | Una tarea o cambio acotado. | `develop` | `develop` | Ninguno (solo CI) |
| `release/x.y.z` | Congelar una versión candidata y estabilizarla. | `develop` | `main` y `develop` | Test |
| `hotfix/descripcion` | Corrección urgente de producción. | `main` | `main` y `develop` | Prod (con aprobación manual) |

Reglas:

1. **Nadie hace push directo a `main` ni a `develop`.** Todo cambio entra por Pull Request.
2. **Cada PR requiere al menos 1 aprobación de una persona distinta del autor.** Se aplica con branch protection (ver DEVOPS-18) y con `CODEOWNERS`.
3. **Los checks de CI deben pasar antes de fusionar** (se agregan como obligatorios a medida que el pipeline existe, a partir del Sprint 2).
4. **Nombres de rama:** `feature/DEVOPS-XX-descripcion-corta`, con la clave de Jira, para que Jira vincule ramas, commits y PRs automáticamente.
5. **Mensajes de commit** con la clave de Jira, por ejemplo `DEVOPS-30: sacar secretos del repo`.
6. **La misma imagen se promueve entre ambientes.** La imagen se construye una vez y se etiqueta con el SHA de git. Promover a Test o a Prod no reconstruye: reutiliza esa imagen, de modo que lo que se probó es lo que se despliega.
7. **Los hotfix se fusionan a `main` y a `develop`**, para que la corrección no se pierda en la siguiente versión.

### Organización de repositorios

El código se organiza en dos repositorios, `tero-app` (microservicios, Dockerfiles y pipelines de aplicación) y `tero-infra` (Terraform, Lambda y pipeline de infraestructura). Ambos usan la misma estrategia de ramas.

Se separan porque la aplicación y la infraestructura cambian con ritmos y riesgos distintos, y porque la rúbrica evalúa la separación adecuada de componentes. En `tero-infra` los cambios llegan a Test y Prod con la misma aprobación manual que en la aplicación.

## Alternativas consideradas

### GitHub Flow (`main` más ramas de feature)

Es la opción más simple, con menos ramas que mantener y menos fricción.

La descartamos porque no refleja los tres ambientes en la estructura de ramas. Con una sola rama larga, saber qué versión está en Dev, en Test y en Prod depende de tags o de la configuración del pipeline, y esa trazabilidad es justo lo que la auditoría observó que falta. Con Git Flow simplificado, el nombre de la rama ya dice a qué ambiente corresponde.

### Trunk-Based Development (con feature flags)

Es la opción más ágil: integración muy frecuente a una sola rama y ramas de vida corta.

La descartamos porque exige feature flags, pruebas automatizadas amplias y una cultura de integración continua que Tero hoy no tiene: el repositorio no tiene ninguna prueba automatizada. Sin esa red de seguridad, integrar siempre a la rama principal aumenta el riesgo de romper producción.

## Consecuencias

**Positivas**

- Cada ambiente tiene una rama asociada, lo que da trazabilidad: se sabe qué versión corre en Dev, en Test y en Prod.
- Los cambios en curso no afectan a producción: `main` solo recibe código que pasó por `develop` y `release`.
- Las reglas de revisión y los quality gates se aplican en puntos bien definidos (los PR hacia `develop`, `release/*` y `main`).
- El flujo es fácil de explicar y de enseñar a quien lo herede.

**Negativas**

- Hay más ramas que mantener que en GitHub Flow, y más PRs por cada cambio que llega a producción. Con una sola persona, esa carga recae toda en la misma.
- La revisión por un tercero distinto del autor se simula con una segunda cuenta de GitHub propia, que aprueba los PRs. Cumple la regla técnica (el autor no puede aprobar su propio PR), pero no aporta una mirada independiente. Por eso los comentarios de revisión deben ser sustantivos y quedar documentados.
- `develop` y `main` pueden desincronizarse, sobre todo después de un hotfix. Mitigación: todo hotfix se fusiona también a `develop`, y se revisa la diferencia entre ramas antes de cada release.
- El ciclo de entrega es más lento que con Trunk-Based. Es una concesión aceptada a cambio de control y trazabilidad.

## Seguimiento

- **DEVOPS-18:** configurar branch protection (PR obligatorio, 1 aprobación, checks obligatorios) y `.github/CODEOWNERS` sobre `main` y `develop`.
- **Sprint 2:** agregar los checks de CI como obligatorios.
- **Sprint 5:** incluir un diagrama de branching en la documentación final.
