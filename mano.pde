import gab.opencv.*;
import processing.video.*;
import java.util.List;
import java.util.ArrayList;

// Variables globales
OpenCV opencv;
Capture video;
PImage src, dst;
ArrayList<Contour> contours;
ArrayList<PVector> handDefects;
ArrayList<PVector> fingerTips;
PVector palmCenter;
boolean handDetected = false;

void setup() {
  size(1024, 768);
  
  // Inicializar cámara
  video = new Capture(this, 1024, 768);
  
  // Inicializar OpenCV
  opencv = new OpenCV(this, 1024, 768);
  
  // Inicializar listas
  handDefects = new ArrayList<PVector>();
  fingerTips = new ArrayList<PVector>();
  
  video.start();
}

void draw() {
  if (video.available()) {
    video.read();
    
    // Procesar imagen para detectar mano
    processHandDetection();
    
    // Mostrar imagen original
    image(video, 0, 0);
    
    // Dibujar detecciones
    drawHandDetection();
    
    // Mostrar información
    displayInfo();
  }
}

void processHandDetection() {
  // Cargar imagen en OpenCV
  opencv.loadImage(video);
  
  // Aplicar filtro de color para detectar piel
  dst = skinDetection(opencv.getSnapshot());
  
  // Aplicar filtros morfológicos
  opencv.loadImage(dst);
  opencv.erode();
  opencv.dilate();
  
  // Encontrar contornos
  contours = opencv.findContours(false, true);
  
  // Procesar el contorno más grande (mano)
  if (contours.size() > 0) {
    Contour handContour = getLargestContour(contours);
    
    if (handContour != null && handContour.area() > 5000) {
      handDetected = true;
      
      // Encontrar defectos de convexidad
      handDefects = findConvexityDefects(handContour);
      
      // Calcular centro de la palma
      palmCenter = calculatePalmCenter(handDefects);
      
      // Detectar puntas de dedos
      fingerTips = detectFingerTips(handContour.getPoints(), palmCenter);
    } else {
      handDetected = false;
    }
  } else {
    handDetected = false;
  }
}

PImage skinDetection(PImage input) {
  PImage result = createImage(input.width, input.height, RGB);
  input.loadPixels();
  result.loadPixels();
  
  for (int i = 0; i < input.pixels.length; i++) {
    color c = input.pixels[i];
    float r = red(c);
    float g = green(c);
    float b = blue(c);
    
    // Convertir a HSV
    float[] hsv = rgbToHsv(r, g, b);
    float h = hsv[0];
    float s = hsv[1];
    float v = hsv[2];
    
    // Filtro de piel en HSV
    if ((h < 19 || h > 150) && s > 25 && s < 220 && v > 30) {
      result.pixels[i] = color(255);
    } else {
      result.pixels[i] = color(0);
    }
  }
  
  result.updatePixels();
  return result;
}

float[] rgbToHsv(float r, float g, float b) {
  r /= 255.0;
  g /= 255.0;
  b /= 255.0;
  
  float max = max(r, max(g, b));
  float min = min(r, min(g, b));
  float h, s, v = max;
  
  float d = max - min;
  s = max == 0 ? 0 : d / max;
  
  if (max == min) {
    h = 0;
  } else {
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  
  return new float[]{h * 180, s * 255, v * 255};
}

Contour getLargestContour(ArrayList<Contour> contours) {
  Contour largest = null;
  float maxArea = 0;
  
  for (Contour contour : contours) {
    if (contour.area() > maxArea) {
      maxArea = contour.area();
      largest = contour;
    }
  }
  
  return largest;
}

ArrayList<PVector> findConvexityDefects(Contour contour) {
  ArrayList<PVector> defects = new ArrayList<PVector>();
  
  // Simplificación: usar algunos puntos del contorno como defectos
  ArrayList<PVector> points = contour.getPoints();
  
  if (points.size() > 10) {
    // Tomar algunos puntos estratégicos como defectos potenciales
    int step = points.size() / 8;
    for (int i = 0; i < points.size(); i += step) {
      defects.add(points.get(i));
    }
  }
  
  return defects;
}

PVector calculatePalmCenter(ArrayList<PVector> defects) {
  if (defects.size() == 0) return new PVector(0, 0);
  
  float centerX = 0;
  float centerY = 0;
  
  for (PVector defect : defects) {
    centerX += defect.x;
    centerY += defect.y;
  }
  
  centerX /= defects.size();
  centerY /= defects.size();
  
  return new PVector(centerX, centerY);
}

ArrayList<PVector> detectFingerTips(ArrayList<PVector> contourPoints, PVector center) {
  ArrayList<PVector> tips = new ArrayList<PVector>();
  
  if (contourPoints.size() < 10 || center == null) return tips;
  
  int interval = 55; // Intervalo para análisis de ángulos
  
  for (int i = 0; i < contourPoints.size(); i++) {
    PVector current = contourPoints.get(i);
    
    // Obtener puntos anterior y siguiente
    int prevIndex = (i - interval + contourPoints.size()) % contourPoints.size();
    int nextIndex = (i + interval) % contourPoints.size();
    
    PVector prev = contourPoints.get(prevIndex);
    PVector next = contourPoints.get(nextIndex);
    
    // Calcular ángulo
    float angle = calculateAngle(prev, current, next);
    
    // Si el ángulo es agudo (posible punta de dedo)
    if (angle < 60) {
      float distToPrev = PVector.dist(current, prev);
      float distToNext = PVector.dist(current, next);
      float distToCenter = PVector.dist(current, center);
      
      // Verificar si es una punta válida
      if (distToPrev > 20 && distToNext > 20 && distToCenter > 50) {
        tips.add(current.copy());
      }
    }
  }
  
  // Filtrar puntas muy cercanas
  return filterNearbyTips(tips);
}

float calculateAngle(PVector p1, PVector p2, PVector p3) {
  PVector v1 = PVector.sub(p3, p1);
  PVector v2 = PVector.sub(p3, p2);
  
  float dot = PVector.dot(v1, v2);
  float mag1 = v1.mag();
  float mag2 = v2.mag();
  
  if (mag1 == 0 || mag2 == 0) return 180;
  
  float angle = acos(dot / (mag1 * mag2));
  return degrees(angle);
}

ArrayList<PVector> filterNearbyTips(ArrayList<PVector> tips) {
  ArrayList<PVector> filtered = new ArrayList<PVector>();
  
  for (PVector tip : tips) {
    boolean tooClose = false;
    
    for (PVector existing : filtered) {
      if (PVector.dist(tip, existing) < 30) {
        tooClose = true;
        break;
      }
    }
    
    if (!tooClose) {
      filtered.add(tip);
    }
  }
  
  return filtered;
}

void drawHandDetection() {
  if (!handDetected) return;
  
  // Dibujar área de trabajo
  stroke(255, 0, 0);
  strokeWeight(2);
  noFill();
  rect(150, 50, 580, 330);
  
  // Dibujar centro de la palma
  if (palmCenter != null) {
    fill(0, 0, 255);
    noStroke();
    ellipse(palmCenter.x, palmCenter.y, 8, 8);
  }
  
  // Dibujar puntas de dedos
  fill(255, 0, 255);
  for (PVector tip : fingerTips) {
    ellipse(tip.x, tip.y, 6, 6);
    
    // Línea del centro a la punta
    if (palmCenter != null) {
      stroke(0, 255, 255);
      strokeWeight(3);
      line(palmCenter.x, palmCenter.y, tip.x, tip.y);
    }
  }
  
  // Dibujar defectos de convexidad
  fill(0, 255, 0);
  noStroke();
  for (PVector defect : handDefects) {
    ellipse(defect.x, defect.y, 4, 4);
  }
}

void displayInfo() {
  fill(200, 0, 0);
  textSize(16);
  
  String status = handDetected ? "Mano detectada" : "Buscando mano...";
  text(status, 50, 40);
  
  if (handDetected) {
    text("Dedos detectados: " + fingerTips.size(), 50, 60);
    
    if (palmCenter != null) {
      text("Centro palma: (" + int(palmCenter.x) + ", " + int(palmCenter.y) + ")", 50, 80);
    }
  }
}

// Función para obtener el número de dedos detectados
int getFingerCount() {
  return handDetected ? fingerTips.size() : 0;
}

// Función para obtener la posición del centro de la palma
PVector getPalmCenter() {
  return palmCenter != null ? palmCenter.copy() : new PVector(0, 0);
}

// Función para obtener las posiciones de las puntas de los dedos
ArrayList<PVector> getFingerTips() {
  return new ArrayList<PVector>(fingerTips);
}
