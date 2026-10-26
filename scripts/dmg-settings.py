# Configuración de dmgbuild para la ventana de instalación de Claudio.
# La usa scripts/make-dmg.sh, que pasa las rutas con -D app=… -D background=….
app = defines["app"]                # noqa: F821 (lo define dmgbuild)
background = defines["background"]  # noqa: F821 (con su @2x al lado para pantallas Retina)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

# Ventana de 660 × 400 con la app a la izquierda y Aplicaciones a la derecha;
# las posiciones coinciden con las de scripts/make_dmg_background.py.
window_rect = ((200, 120), (660, 400))
icon_size = 128
text_size = 13
icon_locations = {
    "Claudio.app": (180, 190),
    "Applications": (480, 190),
}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_icon_view_settings = True
