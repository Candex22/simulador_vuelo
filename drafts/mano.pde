import java.net.*;
import java.io.*;
import java.util.*;

// ===== TCP Client for MediaPipe =====
Socket socket;
BufferedReader input;

// ===== Hands data =====
ArrayList<HandData> hands;
String[] gesture_labels = { "Abierto", "Puño" };
HandGestureClassifier handClassifier;

// Control state
int leftHandGesture = -1;
int rightHandGesture = -1;
String controlStatus = "Sin control";

// Point history
ArrayList<PVector> point_history;
int history_length = 16;

// FPS
int fps = 0;
int lastTime = 0;
int frameCount = 0;

void setup() {
  size(960, 540);
  background(0);

  // Initialize variables
  hands = new ArrayList<HandData>();
  handClassifier = new HandGestureClassifier();
  point_history = new ArrayList<PVector>();

  // Connect to Python MediaPipe server
  try {
    socket = new Socket("127.0.0.1", 5005);
    input = new BufferedReader(new InputStreamReader(socket.getInputStream()));
    println("Connected to Python MediaPipe server");
  } catch (Exception e) {
    println("Cannot connect to Python server: " + e.getMessage());
  }
}

void draw() {
  background(0);
  calculateFPS();

  // Read hands from Python
  readMediaPipeHands();

  // Reset gestures
  leftHandGesture = -1;
  rightHandGesture = -1;

  // Process each hand and classify gestures
  for (HandData hand : hands) {
    // Draw landmarks
    for (PVector p : hand.landmarks) {
      fill(255, 0, 0);
      stroke(255, 255, 0);
      ellipse(p.x, p.y, 10, 10);
    }

    // Draw hand label
    if (hand.landmarks.size() > 0) {
      PVector wrist = hand.landmarks.get(0);
      fill(0, 200);
      noStroke();
      rect(wrist.x - 40, wrist.y - 50, 80, 30);
      fill(255);
      textSize(18);
      textAlign(CENTER, CENTER);
      text(hand.label, wrist.x, wrist.y - 35);
    }

    // Classify gesture
    if (hand.landmarks.size() == 21) {
      int gestureId = handClassifier.classify(hand);
      
      // Store gesture by hand
      if (hand.label.equals("Left")) {
        leftHandGesture = gestureId;
      } else if (hand.label.equals("Right")) {
        rightHandGesture = gestureId;
      }
      
      drawGestureInfo(hand, gestureId);
    }
  }

  // Apply two-hand control logic
  applyTwoHandControl();

  drawFPS();
  drawControlStatus();
}

// ===== Read hands from Python server =====
void readMediaPipeHands() {
  if (input != null) {
    try {
      if (input.ready()) {
        String line = input.readLine();
        if (line != null && line.length() > 0) {
          JSONArray handsArray = parseJSONArray(line);
          hands.clear();
          
          for (int h = 0; h < handsArray.size(); h++) {
            JSONObject handObj = handsArray.getJSONObject(h);
            String label = handObj.getString("label");
            JSONArray landmarksArray = handObj.getJSONArray("landmarks");
            
            HandData hand = new HandData();
            hand.label = label;
            
            for (int i = 0; i < landmarksArray.size(); i++) {
              JSONArray lm = landmarksArray.getJSONArray(i);
              float x = lm.getFloat(0) * width;
              float y = lm.getFloat(1) * height;
              hand.landmarks.add(new PVector(x, y));
            }
            
            hands.add(hand);
          }
        }
      }
    } catch (Exception e) {
      println("Error reading MediaPipe: " + e.getMessage());
    }
  }
}

// ===== Two-hand control logic =====
void applyTwoHandControl() {
  // Default: maintain straight flight (no control input)
  controlStatus = "Vuelo recto";
  
  // Check if we have valid gestures from both hands
  boolean leftValid = (leftHandGesture == 0 || leftHandGesture == 1); // 0=Abierto, 1=Puño
  boolean rightValid = (rightHandGesture == 0 || rightHandGesture == 1);
  
  if (!leftValid || !rightValid) {
    // No valid control - maintain straight flight
    controlStatus = "Sin control detectado";
    return;
  }
  
  // Both hands open (0=Abierto) - Pitch up
  if (leftHandGesture == 0 && rightHandGesture == 0) {
    controlStatus = "Cabeceo ARRIBA ↑";
    return;
  }
  
  // Both hands closed (1=Puño) - Pitch down
  if (leftHandGesture == 1 && rightHandGesture == 1) {
    controlStatus = "Cabeceo ABAJO ↓";
    return;
  }
  
  // Right open + Left closed - Turn right
  if (rightHandGesture == 0 && leftHandGesture == 1) {
    controlStatus = "Giro DERECHA →";
    return;
  }
  
  // Left open + Right closed - Turn left
  if (leftHandGesture == 0 && rightHandGesture == 1) {
    controlStatus = "Giro IZQUIERDA ←";
    return;
  }
  
  // Any other combination - maintain straight flight
  controlStatus = "Vuelo recto (combinación no definida)";
}

// ===== Draw gesture info =====
void drawGestureInfo(HandData hand, int gestureId) {
  if (hand.landmarks.size() > 0) {
    PVector wrist = hand.landmarks.get(0);
    fill(0, 150);
    noStroke();
    rect(wrist.x - 60, wrist.y + 20, 120, 30);
    fill(255);
    textSize(14);
    textAlign(CENTER, CENTER);
    String gestureText = (gestureId >= 0 && gestureId < gesture_labels.length) ? gesture_labels[gestureId] : "Unknown";
    text(gestureText, wrist.x, wrist.y + 35);
  }
}

// ===== Draw control status =====
void drawControlStatus() {
  fill(0, 200);
  noStroke();
  rect(width - 280, 10, 270, 100, 8);
  
  fill(255);
  textAlign(LEFT, TOP);
  textSize(14);
  text("Control:", width - 270, 20);
  
  textSize(18);
  fill(0, 255, 100);
  text(controlStatus, width - 270, 45);
  
  textSize(12);
  fill(200);
  text("Izq: " + getGestureName(leftHandGesture), width - 270, 75);
  text("Der: " + getGestureName(rightHandGesture), width - 150, 75);
}

String getGestureName(int gestureId) {
  if (gestureId < 0 || gestureId >= gesture_labels.length) {
    return "---";
  }
  return gesture_labels[gestureId];
}

// ===== FPS =====
void calculateFPS() {
  frameCount++;
  if (millis() - lastTime > 1000) {
    fps = frameCount;
    frameCount = 0;
    lastTime = millis();
  }
}

void drawFPS() {
  fill(255);
  textSize(14);
  textAlign(LEFT);
  text("FPS: " + fps, 10, 20);
}

// ===== HandData class =====
class HandData {
  String label;  // "Left" or "Right"
  ArrayList<PVector> landmarks;
  
  HandData() { 
    label = "";
    landmarks = new ArrayList<PVector>(); 
  }
}

// ===== Gesture classifier - SOLO ABIERTO Y PUÑO =====
class HandGestureClassifier {
  public int classify(HandData hand) {
    if (hand.landmarks == null || hand.landmarks.size() < 21) return -1;

    PVector wrist = hand.landmarks.get(0);
    
    // Tips de los dedos
    PVector thumbTip = hand.landmarks.get(4);
    PVector indexTip = hand.landmarks.get(8);
    PVector middleTip = hand.landmarks.get(12);
    PVector ringTip = hand.landmarks.get(16);
    PVector pinkyTip = hand.landmarks.get(20);
    
    // Base de los dedos (MCPs)
    PVector indexMCP = hand.landmarks.get(5);
    PVector middleMCP = hand.landmarks.get(9);
    PVector ringMCP = hand.landmarks.get(13);
    PVector pinkyMCP = hand.landmarks.get(17);

    // Calcular distancias de las puntas a sus bases
    float indexExtended = dist(indexMCP.x, indexMCP.y, indexTip.x, indexTip.y);
    float middleExtended = dist(middleMCP.x, middleMCP.y, middleTip.x, middleTip.y);
    float ringExtended = dist(ringMCP.x, ringMCP.y, ringTip.x, ringTip.y);
    float pinkyExtended = dist(pinkyMCP.x, pinkyMCP.y, pinkyTip.x, pinkyTip.y);
    
    // Distancias de las bases al wrist
    float indexBase = dist(wrist.x, wrist.y, indexMCP.x, indexMCP.y);
    float middleBase = dist(wrist.x, wrist.y, middleMCP.x, middleMCP.y);
    float ringBase = dist(wrist.x, wrist.y, ringMCP.x, ringMCP.y);
    float pinkyBase = dist(wrist.x, wrist.y, pinkyMCP.x, pinkyMCP.y);
    
    float avgBase = (indexBase + middleBase + ringBase + pinkyBase) / 4.0;

    // Umbral para detectar dedos extendidos
    boolean indexOpen = indexExtended > avgBase * 0.7;
    boolean middleOpen = middleExtended > avgBase * 0.7;
    boolean ringOpen = ringExtended > avgBase * 0.7;
    boolean pinkyOpen = pinkyExtended > avgBase * 0.7;

    // Contar cuántos dedos están extendidos
    int openCount = 0;
    if (indexOpen) openCount++;
    if (middleOpen) openCount++;
    if (ringOpen) openCount++;
    if (pinkyOpen) openCount++;

    // ABIERTO: al menos 3 dedos extendidos
    if (openCount >= 3) {
      return 0; // Abierto
    }
    
    // PUÑO: 0 o 1 dedo extendido
    if (openCount <= 1) {
      return 1; // Puño
    }

    return -1; // Gesto no reconocido
  }
}
