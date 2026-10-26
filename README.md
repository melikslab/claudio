<div align="center">

```
(◕‿◕)   (◔_◔) ..   (•̀ᴗ•́)✎__   (ﾉ◕ヮ◕)ﾉ !   (⊙_⊙) ?
```

# Claudio

**Una mascota ASCII para tu escritorio que te avisa cuando Claude termina, y tus límites de uso en la barra de menús de macOS.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
![Licencia MIT](https://img.shields.io/badge/licencia-MIT-blue)
[![Build](https://github.com/melikslab/claudio/actions/workflows/build.yml/badge.svg)](https://github.com/melikslab/claudio/actions/workflows/build.yml)

*English summary [below](#english).*

</div>

---

Claudio vigila los chats de **Claude Code** en la app de escritorio de Claude (pestaña Code), en el terminal o en el IDE. Una mascota flotante muestra en todo momento qué está haciendo Claude: cuando piensa, trabaja, termina o te necesita. Al terminar, la mascota salta con un **¡!** y un globito con lo último que ha dicho y las respuestas que te propone. Un clic te lleva directamente a ese chat.

No necesita iniciar sesión, no envía nada a ningún sitio y no modifica tu configuración de Claude: solo **lee** ficheros locales.

## Funciones

### 🐾 Mascota flotante
- Siempre encima de las ventanas, visible en todos los escritorios y a pantalla completa.
- Se arrastra a donde quieras y recuerda la posición. Si desconectas un monitor y se queda fuera, vuelve sola a la vista.
- Cada estado tiene su animación ASCII:

  | Estado | Animación |
  |---|---|
  | En reposo | `(◕‿◕)` con parpadeo |
  | Pensando | `(◔_◔) ...` |
  | Trabajando / escribiendo | `(•̀ᴗ•́)✎___` |
  | Terminado | `(ﾉ◕ヮ◕)ﾉ !` |
  | Te necesita (permiso o pregunta) | `(⊙_⊙) ?` |

### 💬 Globito con respuestas rápidas
- Cuando un chat termina, aparece un globito con **el principio del último mensaje** (4 líneas como máximo) y la pregunta, si la hay.
- Muestra **las respuestas que propone Claude**: los botones de fin de turno de la app, las opciones de `AskUserQuestion` o, si no hay, una lista final con pregunta.
- **Clic en una opción:** se copia al portapapeles y se abre ese chat concreto (`claude://code/continue?session=…`). Solo tienes que pegar y pulsar Enter.
- **Clic en el globito o en la mascota:** abre el chat.
- Varios chats a la vez: hasta 3 globitos apilados, un contador naranja y la lista de los que siguen trabajando.

### 📊 Límites de uso en la barra de menús
- **Al pasar el ratón** por el icono: barras como las del panel de Claude para el **límite de sesión (5 h)** y el **semanal**, con su hora de reinicio. Son azules, pasan a **naranja desde el 70 %** y a **rojo desde el 90 %**.
- **Al hacer clic:** el mismo resumen en el menú, más los ajustes.
- Debajo, todos tus chats de los últimos 7 días con su estado. Un clic abre cualquiera.

### 🔔 Avisos
- Sonido y notificación del sistema, configurables por separado para "terminado" y "te necesita".
- Por defecto: sin sonido al terminar y **Pop** cuando pide permiso.
- Opción de avisar solo si la app de Claude no está delante. Al pulsar la notificación se abre el chat.

### ⚙️ Ajustes
Abrir al iniciar el Mac, mostrar u ocultar la mascota, sonidos, notificaciones y botón de prueba.

## Instalación

### Descargar
1. Descarga `Claudio.zip` de la [última release](https://github.com/melikslab/claudio/releases/latest) y descomprímelo.
2. Mueve `Claudio.app` a **Aplicaciones**.
3. La app no está firmada con un certificado de Apple Developer, así que la primera vez macOS la bloquea. Ábrela con **clic derecho → Abrir**, o quita la cuarentena:

```bash
xattr -dr com.apple.quarantine /Applications/Claudio.app
```

### Compilar desde el código
Solo hacen falta las Command Line Tools de Xcode (no Xcode completo):

```bash
git clone https://github.com/melikslab/claudio.git
```

```bash
cd claudio && ./build-app.sh && open build/Claudio.app
```

`build-app.sh` compila en modo release con SwiftPM, monta el paquete `.app` (sin icono en el Dock) y lo firma ad hoc.

## Calibrar el uso

Claude no guarda en disco tu % de uso y no hay una API pública para leerlo sin iniciar sesión. Por eso Claudio **lo estima**:

1. Escribe `/usage` en cualquier chat de la app de Claude.
2. En Claudio, abre **Calibrar con /usage…** (⌘U en el menú, o "Calibrar →" en el desplegable) y copia los dos % y las horas de reinicio.
3. Con eso Claudio calcula a cuánto gasto equivale el 100 % y, desde ahí, va sumando lo que gastan tus chats.

**Cómo sigue sola:** el reinicio semanal es fijo y avanza de 7 en 7 días; la ventana de 5 h empieza con tu primer mensaje tras el reinicio anterior.

> [!NOTE]
> Lo que gastes en claude.ai, en el móvil o en otro ordenador no aparece en este Mac, así que la estimación puede quedarse corta. Recalibra cuando notes que no cuadra; con una vez al día suele bastar.

## Cómo funciona

| Qué | De dónde lo lee |
|---|---|
| Estado de cada chat abierto (`busy` / `idle`, esperando permiso) | `~/.claude/sessions/*.json`, el registro de sesiones de Claude Code |
| Pensando o trabajando, último mensaje y respuestas propuestas | La cola de `~/.claude/projects/*/<sessionId>.jsonl` |
| Título de cada chat, chats dormidos, id para el enlace directo | `~/Library/Application Support/Claude/claude-code-sessions/**/*.json` |
| Gasto para la estimación de uso | Uso de tokens de cada respuesta en `~/.claude/projects/**/*.jsonl`, leído de forma incremental y ponderado por modelo y tipo de token |

```
Sources/Claudio/
├── main.swift             Arranque y modos de depuración (--dump, --parse, --usage, --calibrate)
├── AppDelegate.swift      Monta todo y abre chats con el enlace claude://
├── SessionMonitor.swift   Detecta chats y estados; extrae último mensaje y opciones
├── Pet.swift              Mascota ASCII, globitos y ventana flotante
├── StatusBar.swift        Icono de la barra de menús, desplegable y menú
├── UsageEstimator.swift   Estimación de uso de 5 h y semanal
├── UsageViews.swift       Barras de uso y ventana de calibración
├── Notifier.swift         Sonidos y notificaciones
└── Settings.swift         Ventana de ajustes y abrir al iniciar el Mac
```

### Depuración

```bash
build/Claudio.app/Contents/MacOS/Claudio --dump
```

| Opción | Qué hace |
|---|---|
| `--dump` | Lista los chats detectados con su estado, resumen y opciones |
| `--parse <fichero.jsonl>` | Muestra lo que saldría en el globito para ese historial |
| `--usage` | Imprime la estimación de uso actual |
| `--calibrate <%5h> <reinicio5h> <%semanal> <reinicioSemanal>` | Calibra sin abrir la ventana; las fechas van en ISO 8601, p. ej. `2026-10-26T13:10:00Z` |

## Privacidad

- Solo lee ficheros locales de Claude; no hace peticiones de red.
- No lee credenciales ni tokens, y no modifica `~/.claude/settings.json`.
- Los ajustes y la calibración se guardan en las preferencias de macOS de la app.

## Limitaciones

- Solo ve los chats de **Claude Code** (pestaña Code de la app, CLI o IDE). Los chats normales de claude.ai no se guardan en local.
- No puede escribir en el chat por ti: la app de Claude no tiene ninguna vía para eso. Por eso las opciones se copian al portapapeles y se abre el chat.
- Depende del formato interno de los ficheros de Claude Code, que puede cambiar entre versiones.
- El uso es una estimación (ver [Calibrar el uso](#calibrar-el-uso)).

## Hoja de ruta

- [ ] Mascota con imágenes o sprites animados en lugar de ASCII
- [ ] Recolocar los globitos a izquierda o derecha si la mascota está en un borde
- [ ] Icono de la app
- [ ] Firma y notarización para no tener que quitar la cuarentena

## Créditos

Inspirado en [Claudoscope](https://github.com/cordwainersmith/Claudoscope) de cordwainersmith (MIT), del que toma la idea de leer el estado de Claude Code desde `~/.claude`. Claudio es una reimplementación mucho más sencilla y no reutiliza su código.

Claudio es un proyecto independiente; no está afiliado a Anthropic.

## Licencia

[MIT](LICENSE) © melikslab

---

<a id="english"></a>

### English

**Claudio** is a tiny macOS menu bar app with a draggable ASCII desktop pet that watches your Claude Code chats: the Code tab of the Claude desktop app, the CLI or an IDE. The pet animates while Claude is thinking or working. When Claude finishes, it pops up a bubble with the start of the last reply and the reply options Claude suggested. Clicking an option copies it and jumps straight to that chat.

Hovering over the menu bar icon shows Claude-style bars for your 5-hour and weekly limits. They turn orange at 70 % and red at 90 %. The usage is **estimated** from local chat history and calibrated by hand from `/usage`, so Claudio needs no login.

Claudio is read-only, makes no network calls and needs no changes to your Claude configuration. Build it with `./build-app.sh` (Command Line Tools only). MIT licensed.
