import gab.opencv.*; // Importa la librería OpenCV para Processing
import processing.video.*; // Importa la librería de Video para la captura de cámara
import java.util.Collections; // Para Collections.max/min si es necesario para ordenar puntos

OpenCV opencv;
Capture cam;

// Para seguimiento y visualización
PImage currentFrame;
String gestureText = "Esperando mano...";

// Variables para la lógica de seguimiento de manos 
ArrayList<PVector> bufferCenter = new ArrayList<PVector>();
ArrayList<PVector> bufferFingers = new ArrayList<PVector>();

void settings() {
  size(640, 480); // Establece una resolución común para la webcam
}

void setup() {
  // Inicializa la captura de video
  String[] cameras = Capture.list();
  if (cameras.length == 0) {
    println("No hay cámaras disponibles.");
    exit();
  } else {
    println("Cámaras disponibles:");
    for (int i = 0; i < cameras.length; i++) {
      println(cameras[i]);
    }
    cam = new Capture(this, cameras[0]); // Usa la primera cámara encontrada
    cam.start(); // Comienza la captura de frames
  }

  // Inicializa OpenCV con el contexto del sketch y las dimensiones deseadas
  opencv = new OpenCV(this, width, height);

  // Inicializa los buffers para suavizado
  for (int i = 0; i < 7; i++) bufferCenter.add(new PVector());
  for (int i = 0; i < 5; i++) bufferFingers.add(new PVector());

  // Configura las propiedades de dibujo
  smooth();
  textSize(24);
  textAlign(CENTER, CENTER);
}

void draw() {
  if (cam.available()) {
    cam.read(); // Lee un nuevo frame de la cámara
    currentFrame = cam.get(); // Obtiene la PImage de la cámara

    // Establece la imagen de OpenCV al frame actual
    opencv.loadImage(currentFrame);

    // --- Cadena de Procesamiento de Imagen ---

    // 1. Convierte a HSV para detección de piel
    opencv.toHsv();

    // 2. Detección de piel (rango HSV simplificado para tono de piel, ajustar según sea necesario)
    // Este es un rango básico. La detección real de piel puede ser más compleja.
    // H: 0-25 (tonos rojos/naranjas), S: 30-150 (saturación), V: 80-255 (brillo)
    opencv.inRange(color(0, 30, 80), color(25, 150, 255));

    // 3. Operaciones morfológicas (erosionar y luego dilatar para reducción de ruido y rellenado de huecos)
    opencv.erode();
    opencv.erode(); // Aplica erosión dos veces para un efecto más fuerte
    opencv.dilate();
    opencv.dilate(); // Aplica dilatación dos veces para un efecto más fuerte


    // Muestra la máscara procesada (opcional, para depuración)
    // image(opencv.get ); // Esto mostrará la máscara en blanco y negro

    // 4. Encuentra contornos
    // true para contornos externos, false para aproximación simple
    ArrayList<Contour> contours = opencv.findContours(true, false);

    PVector handCenter = new PVector(0, 0);
    ArrayList<PVector> fingers = new ArrayList<PVector>();

    // Procesa el contorno más grande
    if (contours.size() > 0) {
      Contour largestContour = null;
      float maxArea = 0;
      for (Contour c : contours) {
        float area = c.area();
        if (area > maxArea && area > 2000) { // Filtra por área mínima para evitar ruido pequeño
          maxArea = area;
          largestContour = c;
        }
      }

      if (largestContour != null) {
        // Dibuja el contorno principal (opcional)
        noFill();
        stroke(0, 255, 0);
        strokeWeight(2);
        largestContour.draw();

        // Calcula el Casco Convexo y los Defectos de Convexidad
        ArrayList<PVector> hullPoints = largestContour.convexHull();
        ArrayList<PVector> defectPoints = largestContour.convexityDefects(hullPoints);

        // Dibuja el Casco Convexo (opcional)
        stroke(140, 140, 140);
        if (hullPoints.size() > 1) {
          for (int i = 0; i < hullPoints.size(); i++) {
            PVector p1 = hullPoints.get(i);
            PVector p2 = hullPoints.get((i + 1) % hullPoints.size());
            line(p1.x, p1.y, p2.x, p2.y);
          }
        }

        // Filtra los defectos y encuentra el centro de la palma
        ArrayList<PVector> filteredDefects = new ArrayList<PVector>();
        for (PVector d : defectPoints) {
          // Es posible que necesites ajustar este umbral de profundidad
          // El código Java original usaba buff[3]/256 > sogliaprofondita (donde sogliaprofondita era 5)
          // La librería de Processing podría devolver una estructura diferente para los defectos.
          // Para simplificar, simplemente agregaremos el punto si se considera un defecto.
          // Es posible que necesites inspeccionar la estructura de defectPoints si esto no es preciso.
          filteredDefects.add(d);
          fill(0, 255, 0);
          noStroke();
          ellipse(d.x, d.y, 12, 12); // Dibuja los puntos de defecto
        }

        if (filteredDefects.size() > 0) {
          handCenter = getMinEnclosingCircleCenter(filteredDefects);
          handCenter = applyMovingAverage(bufferCenter, handCenter); // Suaviza el centro de la palma
          fill(0, 0, 255);
          ellipse(handCenter.x, handCenter.y, 6, 6); // Dibuja el centro de la palma
        }

        // Encuentra las puntas de los dedos (lógica simplificada)
        // Este es un método común: encontrar puntos en el contorno que están lejos del centro de la palma
        // y tienen un ángulo agudo.
        ArrayList<PVector> rawFingerTips = new ArrayList<PVector>();
        if (handCenter.x != 0 || handCenter.y != 0) {
            int interval = 25; // Intervalo ajustado para Processing (imagen más pequeña)
            ArrayList<PVector> contourPoints = largestContour.getPoints();

            for (int i = 0; i < contourPoints.size(); i++) {
                PVector vertex = contourPoints.get(i);
                PVector prev, next;

                // Maneja el ajuste alrededor de la lista de contornos
                if (i - interval >= 0) {
                    prev = contourPoints.get(i - interval);
                } else {
                    prev = contourPoints.get(contourPoints.size() + (i - interval));
                }

                if (i + interval < contourPoints.size()) {
                    next = contourPoints.get(i + interval);
                } else {
                    next = contourPoints.get((i + interval) - contourPoints.size());
                }

                // Calcula el ángulo en el vértice (candidato a punta de dedo)
                float angle = PVector.angleBetween(PVector.sub(vertex, next), PVector.sub(vertex, prev));
                angle = degrees(angle); // Convierte radianes a grados

                // Comprueba si el ángulo es lo suficientemente agudo para una punta de dedo
                if (angle < 70) { // Umbral de ángulo para puntas de dedos (ajustar según sea necesario)
                    // Comprueba si el candidato a punta de dedo está más lejos del centro de la palma que sus vecinos
                    float distCenterVertex = PVector.dist(vertex, handCenter);
                    float distCenterPrev = PVector.dist(prev, handCenter);
                    float distCenterNext = PVector.dist(next, handCenter);

                    if (distCenterVertex > distCenterPrev && distCenterVertex > distCenterNext) {
                        rawFingerTips.add(vertex);
                    }
                }
            }
        }
        
        // Agrupa las puntas de los dedos crudas en dedos distintos (similar a tu método Java dita)
        if (rawFingerTips.size() > 0) {
            fingers = groupFingers(rawFingerTips, 20); // 20 es el umbral de distancia para agrupar puntos
            if (fingers.size() > 0) {
                // Aplica el promedio móvil al dedo principal si solo se detecta uno
                if (fingers.size() == 1) {
                    fingers.set(0, applyMovingAverage(bufferFingers, fingers.get(0)));
                }

                // Dibuja los dedos detectados y las líneas al centro de la palma
                stroke(0, 255, 255);
                strokeWeight(2);
                for (PVector finger : fingers) {
                    line(handCenter.x, handCenter.y, finger.x, finger.y);
                    fill(255, 0, 255);
                    noStroke();
                    ellipse(finger.x, finger.y, 6, 6);
                }
            }
        }
    }

    // Actualiza el texto del gesto basándose en el número de dedos
    updateGestureText(fingers.size());
  }

  // Dibuja el frame actual (video original)
  image(currentFrame, 0, 0);

  // Dibuja la máscara procesada superpuesta (para depuración, comentar en la versión final)
  // tint(255, 100); // Hace la máscara semitransparente
  // image(opencv.get, 0, 0);
  // noTint();

  // Superpone el texto del gesto
  fill(200, 0, 0);
  text(gestureText, width / 2, 30);
}

// Función personalizada para calcular el centro del círculo mínimo envolvente
// Esta es una versión simplificada; minEnclosingCircle de OpenCV es más robusto
PVector getMinEnclosingCircleCenter(ArrayList<PVector> points) {
  if (points.isEmpty()) return new PVector(0, 0);
  
  // Promedio simple para demostración; un verdadero círculo mínimo envolvente es más complejo
  PVector center = new PVector(0, 0);
  for (PVector p : points) {
    center.add(p);
  }
  center.div(points.size());
  return center;
}


// Aplica un filtro de promedio móvil simple a un punto
PVector applyMovingAverage(ArrayList<PVector> buffer, PVector current) {
  if (current.x == 0 && current.y == 0) return buffer.get(0); // Si el punto actual es (0,0), devuelve el último válido
  
  for (int i = buffer.size() - 1; i > 0; i--) {
    buffer.set(i, buffer.get(i - 1));
  }
  buffer.set(0, current);

  PVector avg = new PVector(0, 0);
  for (PVector p : buffer) {
    avg.add(p);
  }
  avg.div(buffer.size());
  return avg;
}


// Agrupa los candidatos a puntas de dedos crudas en dedos distintos
ArrayList<PVector> groupFingers(ArrayList<PVector> rawFingerTips, float maxDistance) {
    ArrayList<PVector> distinctFingers = new ArrayList<PVector>();
    if (rawFingerTips.isEmpty()) return distinctFingers;

    // Ordena los puntos por coordenada X para ayudar con el agrupamiento
    Collections.sort(rawFingerTips, (p1, p2) -> Float.compare(p1.x, p2.x));

    PVector currentGroupSum = new PVector();
    int currentGroupCount = 0;

    currentGroupSum.add(rawFingerTips.get(0));
    currentGroupCount = 1;

    for (int i = 1; i < rawFingerTips.size(); i++) {
        PVector prevPoint = rawFingerTips.get(i-1);
        PVector currentPoint = rawFingerTips.get(i);

        if (PVector.dist(prevPoint, currentPoint) < maxDistance) {
            currentGroupSum.add(currentPoint);
            currentGroupCount++;
        } else {
            distinctFingers.add(PVector.div(currentGroupSum, currentGroupCount));
            currentGroupSum = new PVector(currentPoint.x, currentPoint.y);
            currentGroupCount = 1;
        }
    }
    distinctFingers.add(PVector.div(currentGroupSum, currentGroupCount)); // Agrega el último grupo

    // Maneja el posible "wrap-around" para el primer y último grupo si están muy cerca
    if (distinctFingers.size() > 1) {
        PVector first = distinctFingers.get(0);
        PVector last = distinctFingers.get(distinctFingers.size() - 1);
        if (PVector.dist(first, last) < maxDistance) {
            PVector merged = PVector.add(first, last).div(2);
            distinctFingers.set(0, merged);
            distinctFingers.remove(distinctFingers.size() - 1);
        }
    }

    return distinctFingers;
}


void updateGestureText(int numFingers) {
  switch (numFingers) {
    case 0:
      gestureText = "Puño / No se detecta mano";
      break;
    case 1:
      gestureText = "Un Dedo (Puntero)";
      break;
    case 2:
      gestureText = "Dos Dedos";
      break;
    case 3:
      gestureText = "Tres Dedos";
      break;
    case 4:
      gestureText = "Cuatro Dedos";
      break;
    case 5:
      gestureText = "Cinco Dedos (Mano Abierta)";
      break;
    default:
      gestureText = "Reconociendo...";
      break;
  }
}
