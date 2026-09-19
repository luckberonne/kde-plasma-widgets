# KDE Plasma Widgets

Dos widgets para Plasma 6 pensados para usarse juntos en el escritorio: un reloj panorámico y un monitor del sistema, con una estética consistente (fondo transparente, tipografía en blanco con sombra para mantener el contraste sobre cualquier fondo de escritorio).

![Captura del reloj y el monitor del sistema en el escritorio](screenshots/desktop.png)

## Reloj Panorámico (`com.lucas.digitalclock`)

Reloj digital con la hora en grande, el día de la semana en cursiva superpuesto y la fecha debajo, todo en español.

- Formato de hora de 12 o 24 horas, con segundos opcionales.
- Separador de hora configurable (por defecto `.`, ej: `19.33`).
- Mostrar u ocultar la fecha y el día de la semana.
- Incluye la tipografía [Dancing Script](https://fonts.google.com/specimen/Dancing+Script) (licencia SIL Open Font License) para el día de la semana.

## Monitor del Sistema (`com.lucas.sysmonitor`)

Panel de métricas con anillos de progreso para CPU, RAM, GPU dedicada (NVIDIA), GPU integrada (AMD) y disco.

- Uso de CPU calculado en tiempo real a partir de `/proc/stat`.
- Temperatura de CPU vía `k10temp`/`coretemp` (lm-sensors).
- GPU dedicada vía `nvidia-smi` (uso, temperatura, VRAM).
- GPU integrada AMD vía `amdgpu` (lm-sensors) y `gpu_busy_percent` (sysfs).
- Uso de disco de la ruta que elijas (por defecto `/`).
- Representación compacta para el panel (anillos pequeños) con tooltip detallado al pasar el mouse, y representación completa para el escritorio.
- Diseño horizontal (fila) o vertical (columna) a elección, para acomodarlo mejor según el espacio del escritorio.
- Intervalo de actualización configurable.

### Requisitos

- `lm_sensors` (comando `sensors`) para las temperaturas.
- `nvidia-smi` si tenés GPU NVIDIA (opcional, el widget funciona sin ella).
- Un GPU AMD con driver `amdgpu` para la métrica de GPU integrada (opcional).

## Dock de Vidrio (`com.lucas.glassdock`)

Gestor de tareas para el panel con magnificación de iconos al pasar el mouse, al estilo del dock de macOS.

- Los iconos se agrandan según la distancia al puntero, con una curva coseno suave, y los vecinos se separan para acompañar el movimiento.
- El layout es función pura de la posición del puntero (se calcula sobre las celdas base, no sobre las ya escaladas), así que no hay realimentación ni temblor.
- El tamaño del applet no cambia durante la magnificación: el espacio del zoom queda reservado de antemano, por lo que no empuja al resto de los widgets del panel.
- El tamaño base del icono se limita solo para que el zoom nunca quede recortado contra el borde del panel.
- Lanzadores fijos y ventanas abiertas en la misma tira, con un punto indicador por cada ventana abierta (acotado a 3, para no saturar el borde) y atenuación de las minimizadas.
- Miniatura en vivo de las ventanas abiertas al pasar el mouse (vía PipeWire en Wayland, hasta 12 en una grilla de 4 columnas), con clic para saltar a la ventana; si el stream no está disponible cae al icono de la aplicación.
- Arrastrá un `.desktop` a un espacio vacío del dock para fijarlo como lanzador nuevo.
- Arrastrá archivos sobre un icono para abrirlos con esa aplicación; si te quedás encima sin soltar, la ventana se trae al frente (spring-loading) para soltar directamente adentro.
- Rebote continuo mientras una aplicación arranca (hasta que aparece su ventana), clic para activar/minimizar, clic con la rueda del medio para cerrar todas las ventanas de la app (o, sobre una miniatura, solo esa ventana) y menú contextual para fijar, desfijar o cerrar.
- Arrastrar un archivo sobre una app con varias ventanas abre un popup con todas para soltar directo en la que elijas; quedarte parado sobre una la trae al frente sin cerrar el popup, para soltar en la ventana real en vez de en la miniatura.
- En una app con varias ventanas, al quedarte parado sobre su icono empieza a mostrar una miniatura en vivo de cada ventana por turnos, en lugar del icono; clic para ir justo a la que se está mostrando. Desactivado por defecto.
- Insignia con las notificaciones sin leer de cada app (las que llegaron desde la última vez que la usaste) y barra de progreso de sus trabajos en curso: copias de Dolphin, descargas, etc. Se toman del servidor de notificaciones de Plasma.
- Indicador de audio sobre el icono de la app que está sonando, con clic para silenciarla o reactivar el sonido.
- Preferencias por app: clic derecho → "Sin insignias ni audio para esta app" excluye esa app puntual de ambas cosas, sin afectar al resto.
- Rueda del mouse sobre un icono para recorrer las ventanas de esa app, y atajos Meta+1…9 para activar la app según su posición (el widget declara `org.kde.plasma.multitasking`, que es lo que busca plasmashell para esos atajos).
- Reordenar los iconos arrastrándolos; el orden de las apps fijadas se guarda al soltar. Si sacás un lanzador fijo fuera del propio dock (por ejemplo hacia el dock de otra pantalla), pasa a ser un arrastre real del sistema: se fija en el dock donde lo sueltes y se quita del original.
- Publica la posición de cada icono a KWin, así la animación de minimizar (lámpara mágica, squash) va hacia el icono correcto.
- Funciona en paneles horizontales y verticales: el icono crece siempre hacia adentro desde el borde de la pantalla.
- Opción para ocultar el fondo del panel que lo contiene (panel completamente transparente, sin desenfoque), usando el mecanismo propio de Plasma (`backgroundHints: NoBackground` en el contenedor).
- Configurable: tamaño del icono, factor de magnificación, alcance, separación de vecinos, etiquetas y miniaturas al hover, rebote y filtros por escritorio o pantalla.

## Panel Transparente (`com.lucas.paneltransparente`)

Botón mínimo para el panel que alterna su transparencia total.

- Al activarlo, el contenedor del panel pasa a `backgroundHints: NoBackground` (mismo mecanismo que la opción equivalente de Dock de Vidrio), así que el panel queda sin fondo ni desenfoque.
- El icono cambia entre ojo abierto/tachado según el estado, y el estado se guarda en la configuración del widget.
- Sirve para cualquier panel, no requiere reemplazar el gestor de tareas por Dock de Vidrio.

## Velocidad de Red (`com.lucas.netspeed`)

Velocidad de bajada y subida en vivo, con mini gráfico de los últimos 60 muestreos.

- Lee los contadores de `/proc/net/dev`; por defecto usa la interfaz de la ruta por defecto (`ip route`), o la que indiques (ej. `wlan0`).
- Representación compacta para el panel (↓ y ↑ en dos líneas) y completa para el escritorio, con cambio automático por tamaño.
- Unidades automáticas (B/s, KB/s, MB/s, GB/s) y tooltip con la interfaz en uso.
- Configurable: interfaz, intervalo de actualización y mostrar/ocultar el gráfico.

## Chat con LLM Local (`com.lucas.llmchat`)

Chat, traductor y corrector que usan tu propio modelo local vía la API compatible con OpenAI de `llama-server` (llama.cpp).

- Cuatro modos: **Chat** (con historial de la sesión), **Traducir** (español ↔ inglés automático), **Corregir** (ortografía y gramática sin cambiar el sentido) y **Comando** (describís una tarea en lenguaje natural y devuelve el comando de terminal para copiar; nunca lo ejecuta).
- Respuestas en streaming, botón para detener, copiar la respuesta y limpiar la conversación.
- Enter envía, Shift+Enter agrega salto de línea.
- Se abre desde un icono en el panel (o como widget de escritorio).
- Configurable: URL del servidor (por defecto `http://127.0.0.1:8080`), temperatura y prompt del sistema del modo chat.
- Todo queda en tu máquina: no se envía nada a servicios externos.

### Requisitos

- Un `llama-server` corriendo, por ejemplo: `llama-server -m modelo.gguf --host 127.0.0.1 --port 8080`.

## Contenedores Docker (`com.lucas.docker`)

Bandeja de contenedores de Docker: estado de un vistazo y control básico sin abrir la terminal.

- En un panel se ve como un icono con un contador verde de contenedores en ejecución y, al hacer clic, se despliega la lista (con el tema de Plasma). En el escritorio se muestra directamente con estilo glass. Una tarjeta por contenedor (nombre, imagen, estado, puertos publicados).
- Indicador de color: verde en ejecución, ámbar en pausa o `unhealthy`, gris detenido.
- Botones para iniciar/detener, reiniciar y ver logs (últimas N líneas, con botón para copiarlos).
- Configurable: intervalo de actualización, mostrar o no los detenidos y cantidad de líneas de log.
- Si Docker no está disponible o tu usuario no tiene permisos, lo muestra en el widget.

### Requisitos

- `docker` en el `PATH` y tu usuario en el grupo `docker`.

## Servidor LLM (`com.lucas.llmserver`)

Estado de tu servidor [llama.cpp](https://github.com/ggml-org/llama.cpp) (`llama-server`) y control de su servicio de systemd de usuario. Complementa a Chat con LLM Local.

- Estado: Detenido, Iniciando, Listo o Generando, con un punto de color (que pulsa mientras genera) también en el icono del panel.
- Tokens por segundo: en vivo mientras genera y promedio de la última generación. Se calcula a partir de `/slots`, así que no hace falta arrancar el servidor con `--metrics`.
- Contexto ocupado por la última petición, VRAM que usa el proceso del servidor (`nvidia-smi`), RAM del servicio, tiempo activo y nombre del modelo.
- Botones para iniciar, detener y reiniciar el servicio (`systemctl --user`).
- En un panel se ve como un icono con desplegable con el tema de Plasma; en el escritorio, con estilo glass.
- Configurable: URL del servidor, nombre de la unidad systemd (por defecto `llama-server.service`) e intervalo de actualización.
- No consulta la GPU mientras el servicio está detenido, para no despertar la dedicada en equipos híbridos.

### Requisitos

- `llama-server` corriendo como servicio de usuario de systemd (`~/.config/systemd/user/llama-server.service`).
- `nvidia-smi` para la VRAM (opcional).

## Tailscale (`com.lucas.tailscale`)

Estado de tu red [Tailscale](https://tailscale.com) y de sus dispositivos, con conexión y desconexión con un clic.

- Icono de panel con un punto de color (verde conectado, gris desconectado, ámbar si requiere inicio de sesión) y desplegable con el tema de Plasma; en el escritorio se ve con estilo glass.
- Interruptor para conectar o desconectar (`tailscale up` / `tailscale down`).
- Este equipo con su IP, y la lista de dispositivos con sistema operativo, IP, si están en línea o cuándo se los vio por última vez, y si alguno es exit node.
- Copiar con un clic la IP o el nombre MagicDNS de cualquier dispositivo.
- Muestra los avisos de salud de Tailscale y un botón de inicio de sesión cuando hace falta.
- Configurable: intervalo de actualización y mostrar u ocultar los dispositivos desconectados.

### Requisitos

- `tailscale` y `tailscaled` funcionando.
- Para que el interruptor funcione sin `sudo`, hay que configurar tu usuario como operador una sola vez: `sudo tailscale set --operator=$USER`. Si falta, el widget te muestra este comando.

## Botonera de Comandos (`com.lucas.commanddeck`)

Botonera de comandos personalizables, al estilo Stream Deck: un botón, un comando.

- Cuadrícula de teclas de vidrio translúcido, cada una con icono, nombre y color propios (5 × 3 por defecto, con las ranuras libres marcadas con un «+»); en un panel se ve como un icono con desplegable.
- Editor en la configuración del widget: añadir, eliminar y reordenar botones, elegir el icono del tema de Plasma, el color y el comando.
- Cada botón muestra su resultado: giro mientras corre, verde si terminó bien y rojo si falló (con la primera línea de la salida o el código de error en el pie).
- Opciones por botón: aplicación (no espera a que termine, ideal para lanzar programas), abrir en una terminal Konsole que queda abierta, y pedir confirmación antes de ejecutar (para cosas como suspender).
- Configurable: columnas, tamaño de los botones y mostrar u ocultar las etiquetas.
- Viene con seis botones de ejemplo: bloquear, captura, terminal, silenciar, suspender y reiniciar Plasma.

Los comandos se ejecutan con `sh -c` y tus permisos de usuario, así que sirven los mismos que en una terminal.

## Energía (`com.lucas.energia`)

Batería, consumo en vatios y perfil de energía con un clic.

- Porcentaje y estado (cargando, descargando o completa) con el tiempo estimado hasta vaciarse o llenarse, calculado a partir del consumo actual.
- Consumo en vatios en vivo con un gráfico de los últimos 60 muestreos, salud de la batería (capacidad actual frente a la de diseño) y ciclos de carga.
- Botones para cambiar entre los perfiles de `power-profiles-daemon`: Ahorro, Equilibrado y Rendimiento. El color del widget acompaña al perfil activo.
- En un panel se ve como el icono de la batería (con el porcentaje al lado y un punto del color del perfil) y un desplegable con el tema de Plasma; en el escritorio, con estilo glass.
- Configurable: intervalo de actualización, mostrar u ocultar el gráfico y el porcentaje en el panel.

### Requisitos

- `power-profiles-daemon` (comando `powerprofilesctl`) para los perfiles.
- Una batería visible en `/sys/class/power_supply` (en una PC de escritorio el widget solo muestra los perfiles).

## Proyectos Git (`com.lucas.gitprojects`)

Estado de tus repositorios Git de un vistazo, con acceso directo a code-oss y a Claude Code (incluido su historial).

- Busca los repositorios dentro de una carpeta (por defecto `~/Proyectos`, con profundidad configurable) y muestra para cada uno la rama, los cambios sin commitear, los commits sin pushear (↑) o por traer (↓), si no tiene remoto, y cuándo y con qué mensaje fue el último commit.
- Los repos con novedades aparecen primero; el resto, ordenados por el commit más reciente. Un punto de color indica el estado: verde al día, ámbar con cambios, celeste con commits por pushear.
- **code-oss:** botón para abrir el proyecto en el editor (configurable, por defecto `code-oss`) y, debajo de cada repo, cuándo lo abriste por última vez en code-oss (se lee del almacenamiento de workspaces del editor).
- **Claude Code:** botón para abrir una nueva sesión en una terminal (Konsole con fish) ya ubicada en la carpeta del proyecto. Junto a cada repo se ve cuántas sesiones hay y cuándo fue la última.
- **Historial de Claude Code:** al abrirlo, lista las últimas sesiones del proyecto (título tomado del primer mensaje y fecha), con botones para reanudar una sesión (`claude --resume`), continuar la última (`claude --continue`) o empezar una nueva. Al salir de Claude la terminal queda abierta en fish.
- Otros botones: abrir una terminal en esa carpeta, abrir la carpeta y copiar la ruta.
- En un panel se ve como un icono con un contador de repos con novedades y un desplegable con el tema de Plasma; en el escritorio, con estilo glass.
- Configurable: carpeta raíz, profundidad de búsqueda, comando del editor, comando de Claude Code, intervalo de actualización y mostrar solo los repos con novedades.
- Solo consulta el estado local: no hace `git fetch`, así que «por traer» refleja lo último que ya descargaste. El historial de Claude se lee de `~/.claude/projects` y no sale de tu equipo.

### Requisitos

- `git`, Konsole, `fish` y `python3` (para leer los títulos de las sesiones).
- `code-oss` y `claude` en el `PATH` (opcionales: sin ellos solo fallan sus botones).

## Instalación

Copiá cada carpeta a tu directorio de plasmoids de usuario:

```bash
cp -r com.lucas.digitalclock ~/.local/share/plasma/plasmoids/
cp -r com.lucas.sysmonitor ~/.local/share/plasma/plasmoids/
cp -r com.lucas.glassdock ~/.local/share/plasma/plasmoids/
cp -r com.lucas.paneltransparente ~/.local/share/plasma/plasmoids/
```

Reiniciá Plasma para que aparezcan en el selector de widgets:

```bash
plasmashell --replace &
```

Después, clic derecho en el escritorio (o en el panel) → **Agregar widgets** → buscá "Reloj Panorámico" o "Monitor del Sistema".

## Licencia

Código bajo licencia MIT (ver [LICENSE](LICENSE)). La tipografía Dancing Script incluida en `com.lucas.digitalclock/contents/fonts/` se distribuye bajo la SIL Open Font License 1.1 (ver el archivo `OFL.txt` en esa misma carpeta).
