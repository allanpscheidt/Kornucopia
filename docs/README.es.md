# Kornucopia

Kornucopia organiza tu trabajo en un tablero Kanban con notas adhesivas para Mac con Apple Silicon y Windows 11. Las columnas Pendientes, En curso, Revisión y Hecho incluyen un tutorial práctico y un color propio.

**[Descargar la versión más reciente](https://github.com/allanpscheidt/Kornucopia/releases/latest)** · [Português brasileiro](../README.md)

## Versión 1.0.1

- Tutoriales prácticos en las cuatro columnas.
- Interfaz en portugués brasileño, inglés, español, francés y japonés.
- Selección de idioma guardada en Configuración. Tus notas conservan su texto original.
- Paquetes para Mac arm64 y Windows x64 y ARM64.

En curso comienza con un límite de dos tarjetas. Una alerta bloquea la entrada de otra cuando se alcanza el límite. Termina una tarea y muévela a Revisión antes de empezar otra. Puedes aumentar el límite en Configuración. Las demás columnas admiten tarjetas sin un límite artificial.

## Instalar y usar

Los comandos estándar de macOS, como Cerrar, siguen el idioma del sistema. La selección de idioma traduce los controles, las alertas y los tutoriales de Kornucopia.

En Mac se requiere Apple Silicon y macOS 14 o posterior. Extrae el ZIP de macOS arm64 y copia Kornucopia.app a Aplicaciones. El paquete usa una firma ad hoc, sin Developer ID ni notarización de Apple. Consulta la [guía de Apple](https://support.apple.com/es-es/102445) si el sistema bloquea la primera apertura.

En Windows 11, elige el ZIP x64 o ARM64 según tu procesador. Extrae toda la carpeta y conserva Kornucopia.exe junto con Resources. Abre el ejecutable. El paquete incluye el runtime y actualmente no tiene firma Authenticode. Comprueba el origen y conserva las protecciones del sistema.

Registra una idea en Pendientes, edita el título y las notas y sigue las instrucciones de cada columna. Mueve tarjetas arrastrándolas o desde el editor. Elige el idioma y ajusta el límite de trabajo en Configuración. Las columnas mantienen colores distintos: amarillo, azul, morado y verde.

Las modificaciones se guardan automáticamente. Los datos están en `~/Library/Application Support/Kornucopia/` en Mac y `%LOCALAPPDATA%\Kornucopia\` en Windows. Son archivos JSON legibles, con una copia del estado anterior. Incluye la carpeta en tus copias de seguridad. El app funciona localmente, sin cuentas ni sincronización en la nube.

Consulta la [documentación completa](../README.md), la [guía de contribución](../CONTRIBUTING.md) y la [política de seguridad](../SECURITY.md).
