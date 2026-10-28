# Cómo contribuir

¡Gracias por querer mejorar Claudio!

## Preparar el entorno

- macOS 14 o superior.
- Command Line Tools de Xcode (`xcode-select --install`). Xcode completo es opcional.

```bash
./build-app.sh && open build/Claudio.app
```

## Antes de abrir un pull request

1. Comprueba que compila sin errores: `swift build -c release`.
2. Prueba el cambio con la app abierta y, si toca la lectura de chats, con `build/Claudio.app/Contents/MacOS/Claudio --dump`.
3. Sigue el estilo del código que hay alrededor: comentarios breves en español, nombres claros y sin dependencias externas.
4. Añade una línea en [CHANGELOG.md](CHANGELOG.md), en una sección `Sin publicar`.

## Ideas y errores

Abre un issue con la plantilla que corresponda. Si es un error con la detección de chats, incluye la versión de Claude (`ls ~/Library/Application\ Support/Claude/claude-code/`) y la salida de `--dump`. Revísala antes: incluye títulos y fragmentos de tus chats.

## Mascotas nuevas

Hay dos aspectos, los dos en [Pet.swift](Sources/Claudio/Pet.swift), y `PetRenderer` es el único sitio que los dibuja:

- **Animada:** `SpriteFrames` lee [Resources/PetSprites.png](Resources/PetSprites.png), con celdas de 192 × 208 px y una fila por estado: reposo, pensando, trabajando, guiño, cara feliz, te necesita y dormido. Los dibujos van en blanco sobre fondo transparente, porque la app los tiñe con el color elegido. Cada animación indica sus fotogramas, su duración y la zona de la celda que ocupa.
- **ASCII:** `AsciiFrames`, una lista de fotogramas de texto por estado.
