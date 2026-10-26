# Cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones según [SemVer](https://semver.org/lang/es/).

## [0.2.0] - 2026-10-26

### Añadido
- Icono de la app, que también usan las notificaciones y la cabecera de cada globito.
- Los globitos se recolocan solos debajo, a la derecha o a la izquierda de la mascota si no caben encima.

### Cambiado
- La mascota se puede mover libremente por todo el escritorio y por cualquier pantalla; antes no podía subir más allá de cierta altura.
- Al cerrar un globito con la ✕ la mascota deja de llamar la atención (también en "te necesita") hasta el siguiente cambio de estado.
- El parpadeo en reposo es más lento: uno cada 6 segundos.

## [0.1.0] - 2026-10-26

Primera versión.

### Añadido
- Mascota ASCII flotante y arrastrable, con animación para cada estado: reposo, pensando, trabajando, terminado y te necesita.
- Globito al terminar un chat, con el principio del último mensaje (4 líneas como máximo), la pregunta y las respuestas propuestas. Al pulsar una opción se copia y se abre ese chat.
- Detección de todos los chats de Claude Code de los últimos 7 días, incluidos los que la app ha dormido.
- Icono en la barra de menús con desplegable al pasar el ratón: barras de uso de 5 h y semanal al estilo de Claude, en azul, naranja y rojo, y lista de chats.
- Estimación de uso a partir del historial local, calibrada a mano con `/usage`.
- Sonidos y notificaciones configurables por separado para "terminado" y "te necesita".
- Ajustes: abrir al iniciar el Mac, mostrar mascota, sonidos y notificaciones.
- La mascota vuelve sola a la vista si se queda fuera de las pantallas; opción "Recolocar mascota".
- Modos de depuración `--dump`, `--parse`, `--usage` y `--calibrate`.

[0.2.0]: https://github.com/melikslab/claudio/releases/tag/v0.2.0
[0.1.0]: https://github.com/melikslab/claudio/releases/tag/v0.1.0
