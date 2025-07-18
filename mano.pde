import gab.opencv.*;
import processing.video.*;
import java.util.List;
import java.util.ArrayList;

// Variables globales
OpenCV opencv;
Capture video;
PImage processedImage;
ArrayList<Contour> contours;
boolean handDetected = false;
int frameCount = 0;
boolean showProcessed = false;

// Variables de detección
PVector palmCenter;
ArrayList<PVector> fingerTips;
Contour handContour;

void setup() {
  size(1200, 400);
  
  // Inicializar cámara con configuración específica
  String[] cameras = Capture.list();
  if (cameras.length == 0) {
    println("No hay cámaras disponibles");
    exit();
  } else {
    println("Cámaras disponibles:");
    for (int i = 0; i < cameras.length; i++) {
      println(i + ": " + cameras[i]);
    }
  }
  
  // Usar la primera cámara disponible
  video = new Capture(this, 640, 480);
  video.start();
  
  // Inicializar OpenCV
  opencv = new OpenCV(this, 640, 480);
  
  // Inicializar variables
  fingerTips = new ArrayList<PVector>();
  contours = new ArrayList<Contour>();
  
  // Configurar fuente para evitar warnings
  textFont(createFont("Arial", 16, true));
  
  println("Setup completado");
}

void draw() {
  background(0);
  
  // Solo procesar si hay nueva imagen disponible
  if (video.available()) {
    video.read();
  }
  
  // SIEMPRE mostrar la imagen de la cámara, independientemente del procesamiento
  if (video.width > 0) {
    image(video, 0, 0);
  }
  
  // Procesar cada 5 frames para mejor rendimiento (menos frecuente)
  if (frameCount % 5 == 0 && video.width > 0) {
    processHandDetection();
  }
  frameCount++;
  
  // Mostrar imagen procesada si está habilitada
  if (showProcessed && processedImage != null) {
    image(processedImage, 640, 0);
  }
  
  // SIEMPRE dibujar las detecciones (usando los últimos datos calculados)
  drawHandDetection();
  
  // Mostrar información
  displayInfo();
} // <- FALTABA ESTA LLAVE

void processHandDetection() {
  try {
    // Crear una copia de la imagen para no interferir con la visualización
    PImage tempImage = video.copy();
    
    // Aplicar filtro de piel
    processedImage = applySkinFilter(tempImage);
    
    // Cargar imagen filtrada en OpenCV y convertir a escala de grises
    opencv.loadImage(processedImage);
    opencv.gray();
    
    // Aplicar operaciones morfológicas básicas
    opencv.erode();
    opencv.dilate();
    opencv.dilate();
    
    // Obtener imagen procesada final para mostrar
    if (showProcessed) {
      processedImage = opencv.getSnapshot();
    }
    
    // Encontrar contornos
    contours = opencv.findContours(false, true);
    
    // Resetear detección
    handDetected = false;
    handContour = null;
    
    // Buscar el contorno más grande
    if (contours.size() > 0) {
      handContour = getLargestContour(contours);
      
      // Verificar si es lo suficientemente grande para ser una mano
      if (handContour != null && handContour.area() > 3000) {
        handDetected = true;
        
        // Calcular centro simple
        palmCenter = calculateSimpleCenter(handContour);
        
        // Detectar dedos de forma simple
        fingerTips = detectFingersSimple(handContour);
      }
    }
    
  } catch (Exception e) {
    println("Error en procesamiento: " + e.getMessage());
  }
}

PImage applySkinFilter(PImage input) {
  PImage result = createImage(input.width, input.height, RGB);
  input.loadPixels();
  result.loadPixels();
  
  for (int i = 0; i < input.pixels.length; i++) {
    color c = input.pixels[i];
    float r = red(c);
    float g = green(c);
    float b = blue(c);
    
    // Filtro de piel RGB simple pero efectivo
    boolean isSkin = false;
    
    if (r > 95 && g > 40 && b > 20 && 
        r > g && r > b && 
        (r - g) > 15 && 
        (r - b) > 15) {
      isSkin = true;
    }
    
    // Filtro adicional para tonos más oscuros
    if (r > 60 && g > 30 && b > 15 && 
        r > g && r > b && 
        (r - g) > 10) {
      isSkin = true;
    }
    
    result.pixels[i] = isSkin ? color(255) : color(0);
  }
  
  result.updatePixels();
  return result;
}

Contour getLargestContour(ArrayList<Contour> contours) {
  if (contours.size() == 0) return null;
  
  Contour largest = contours.get(0);
  float maxArea = largest.area();
  
  for (Contour contour : contours) {
    if (contour.area() > maxArea) {
      maxArea = contour.area();
      largest = contour;
    }
  }
  
  return largest;
}

PVector calculateSimpleCenter(Contour contour) {
  ArrayList<PVector> points = contour.getPoints();
  if (points.size() == 0) return new PVector(0, 0);
  
  float sumX = 0, sumY = 0;
  
  for (PVector point : points) {
    sumX += point.x;
    sumY += point.y;
  }
  
  return new PVector(sumX / points.size(), sumY / points.size());
}

ArrayList<PVector> detectFingersSimple(Contour contour) {
  ArrayList<PVector> tips = new ArrayList<PVector>();
  ArrayList<PVector> points = contour.getPoints();
  
  if (points.size() < 50) return tips;
  
  // Buscar puntos que estén lejos del centro
  for (int i = 0; i < points.size(); i += 10) {
    PVector point = points.get(i);
    float distToCenter = PVector.dist(point, palmCenter);
    
    // Si está lejos del centro, podría ser un dedo
    if (distToCenter > 60) {
      // Verificar que no esté muy cerca de otro tip ya encontrado
      boolean farFromOthers = true;
      for (PVector existing : tips) {
        if (PVector.dist(point, existing) < 50) {
          farFromOthers = false;
          break;
        }
      }
      
      if (farFromOthers) {
        tips.add(point.copy());
      }
    }
  }
  
  // Limitar a máximo 5 dedos
  while (tips.size() > 5) {
    tips.remove(tips.size() - 1);
  }
  
  return tips;
}

void drawHandDetection() {
  // Dibujar contorno principal si existe
  if (handContour != null) {
    stroke(0, 255, 0);
    strokeWeight(2);
    noFill();
    handContour.draw();
  }
  
  if (!handDetected) return;
  
  // Dibujar centro de la palma
  if (palmCenter != null) {
    fill(255, 0, 0);
    noStroke();
    ellipse(palmCenter.x, palmCenter.y, 15, 15);
  }
  
  // Dibujar puntas de dedos
  fill(0, 255, 255);
  noStroke();
  for (PVector tip : fingerTips) {
    ellipse(tip.x, tip.y, 12, 12);
    
    // Línea del centro a la punta
    if (palmCenter != null) {
      stroke(255, 255, 0);
      strokeWeight(2);
      line(palmCenter.x, palmCenter.y, tip.x, tip.y);
    }
  }
}

void displayInfo() {
  // Fondo semitransparente para mejor legibilidad
  fill(0, 0, 0, 150);
  noStroke();
  rect(5, 5, 300, 140);
  
  fill(255);
  textSize(16);
  
  // Estado de la detección
  String status = handDetected ? "✓ Mano detectada" : "✗ Buscando mano...";
  text(status, 10, 30);
  
  // Información de contornos
  text("Contornos: " + contours.size(), 10, 50);
  
  if (handContour != null) {
    text("Área: " + int(handContour.area()), 10, 70);
  }
  
  if (handDetected) {
    text("Dedos: " + fingerTips.size(), 10, 90);
    
    if (palmCenter != null) {
      text("Centro: (" + int(palmCenter.x) + ", " + int(palmCenter.y) + ")", 10, 110);
    }
  }
  
  // Controles
  text("'P' = mostrar imagen procesada | FPS: " + int(frameRate), 10, 130);
}

void keyPressed() {
  if (key == 'P' || key == 'p') {
    showProcessed = !showProcessed;
  }
}

// Funciones de utilidad
int getFingerCount() {
  return handDetected ? fingerTips.size() : 0;
}

PVector getPalmCenter() {
  return palmCenter != null ? palmCenter.copy() : new PVector(0, 0);
}

ArrayList<PVector> getFingerTips() {
  return new ArrayList<PVector>(fingerTips);
}
