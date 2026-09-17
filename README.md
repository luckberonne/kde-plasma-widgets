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

## Instalación

Copiá cada carpeta a tu directorio de plasmoids de usuario:

```bash
cp -r com.lucas.digitalclock ~/.local/share/plasma/plasmoids/
cp -r com.lucas.sysmonitor ~/.local/share/plasma/plasmoids/
```

Reiniciá Plasma para que aparezcan en el selector de widgets:

```bash
plasmashell --replace &
```

Después, clic derecho en el escritorio (o en el panel) → **Agregar widgets** → buscá "Reloj Panorámico" o "Monitor del Sistema".

## Licencia

Código bajo licencia MIT (ver [LICENSE](LICENSE)). La tipografía Dancing Script incluida en `com.lucas.digitalclock/contents/fonts/` se distribuye bajo la SIL Open Font License 1.1 (ver el archivo `OFL.txt` en esa misma carpeta).
