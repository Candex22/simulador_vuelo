# ✈️ Simulador de Vuelo con Control por Gestos

Un simulador de vuelo 3D controlado con las manos a través de la cámara web, usando MediaPipe para detección de gestos y Processing para el renderizado del mundo.

---

## 🗂️ Estructura del proyecto

```
├── hand_server.py      # Servidor Python: captura gestos con MediaPipe y los envía por TCP
└── integracion.pde     # Sketch de Processing: mundo 3D, física de vuelo y HUD
```

---

## ⚙️ Requisitos

### Python
- Python 3.8+
- OpenCV: `pip install opencv-python`
- MediaPipe: `pip install mediapipe`

### Processing
- [Processing 4](https://processing.org/download)
- Sin librerías externas (usa solo las incluidas en el core)

---

## 🚀 Cómo ejecutar

**Importante:** el servidor Python debe iniciarse **antes** de abrir el sketch de Processing.

### 1. Iniciar el servidor de gestos

```bash
python hand_server.py
```

El servidor abre una cámara web, detecta hasta 2 manos y queda escuchando en `127.0.0.1:5005` esperando la conexión de Processing.

### 2. Abrir y ejecutar el sketch

Abrí `integracion.pde` en Processing y presioná el botón **Run**. El sketch se conecta automáticamente al servidor Python.

---

## 🖐️ Gestos y controles

El simulador reconoce 3 gestos por mano:

| Gesto | Descripción |
|---|---|
| ✋ Mano abierta | 3 o más dedos extendidos |
| ✊ Puño | 1 o ningún dedo extendido |
| ✌️ Paz | Solo índice y medio extendidos |

### Control de vuelo (dos manos)

| Mano izquierda | Mano derecha | Acción |
|---|---|---|
| ✋ Abierta | ✋ Abierta | Cabeceo arriba (pitch up) |
| ✊ Puño | ✊ Puño | Cabeceo abajo (pitch down) |
| ✊ Puño | ✋ Abierta | Giro a la derecha (yaw right) |
| ✋ Abierta | ✊ Puño | Giro a la izquierda (yaw left) |
| ✌️ Paz (cualquiera) | — | Vuelo recto / neutro |

### Control de estado del juego

| Gesto | Acción |
|---|---|
| ✌️✌️ Paz con ambas manos (pantalla de inicio) | Iniciar vuelo |
| ✌️✌️ Paz con ambas manos (en vuelo) | Pausar |
| ✌️✌️ Paz con ambas manos (pausado) | Reanudar |

### Teclado (alternativo)

| Tecla | Acción |
|---|---|
| `W` | Avanzar |
| `S` | Retroceder |
| `A` | Girar derecha |
| `D` | Girar izquierda |
| `R` | Aumentar velocidad máxima |
| `F` | Reducir velocidad máxima |

---

## 🌍 Mundo y características

- Terreno 3D generado proceduralmente con ruido Perlin
- Chunks cargados dinámicamente alrededor de la cámara
- Tipos de terreno: zonas urbanas (edificios con hitboxes), montañas, aeropuertos
- Nubes generadas por chunk
- Límite de altura: **1200 m** (advertencia al superar los 1000 m)

### HUD del piloto

- **Horizonte artificial** con roll y pitch visuales
- **Altímetro** en metros
- **Velocímetro** en unidades/segundo
- **Brújula de rumbo** en grados

---

## 🔧 Arquitectura técnica

```
Cámara web
    ↓
hand_server.py  (MediaPipe → landmarks JSON)
    ↓  TCP localhost:5005
integracion.pde (Processing)
    ├── Clasificador de gestos
    ├── Lógica de control de vuelo
    └── Render 3D del mundo
```

El servidor Python envía por TCP un array JSON por frame con los datos de cada mano detectada:

```json
[
  {
    "label": "Left",
    "landmarks": [[x, y, z], ...]  // 21 puntos
  },
  {
    "label": "Right",
    "landmarks": [[x, y, z], ...]
  }
]
```

---

## 🐛 Solución de problemas

**Processing no se conecta al servidor**
→ Asegurate de haber iniciado `hand_server.py` primero y de que no haya otro proceso usando el puerto 5005.

**No se detectan las manos**
→ Verificá que la cámara web esté disponible y bien iluminada. El umbral de confianza mínima es 0.7.

**El gesto de paz no se reconoce con fluidez**
→ El sistema requiere 15 frames consecutivos con el gesto de paz para activarlo, lo que evita activaciones accidentales.