import java.net.*;
import java.io.*;
import java.util.*;

// ===== TCP Client for MediaPipe =====
Socket socket;
BufferedReader input;

// ===== Gesture and landmarks =====
ArrayList<PVector> mpLandmarks;
HandGestureClassifier handClassifier;
String[] gesture_labels = { "Open", "Three", "Scout", "Peace", "Rock", "Call" };

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
  mpLandmarks = new ArrayList<PVector>();
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

  // Read landmarks from Python
  readMediaPipeLandmarks();

  // Draw landmarks
  for (PVector p : mpLandmarks) {
    fill(255, 0, 0);
    stroke(255, 255, 0);
    ellipse(p.x, p.y, 10, 10);
  }

  // Classify gesture if we have a full hand
  if (mpLandmarks.size() == 21) {
    HandData hand = new HandData();
    hand.landmarks = mpLandmarks;
    int gestureId = handClassifier.classify(hand);

    drawGestureInfo(hand, gestureId);
    updatePointHistory(hand);
  }

  drawPointHistory();
  drawFPS();
}

// ===== Read landmarks from Python server using Processing JSON =====
void readMediaPipeLandmarks() {
  if (input != null) {
    try {
      if (input.ready()) {
        String line = input.readLine();
        if (line != null && line.length() > 0) {
          JSONArray arr = parseJSONArray(line); // Processing built-in JSON
          mpLandmarks.clear();
          for (int i = 0; i < arr.size(); i++) {
            JSONArray lm = arr.getJSONArray(i);
            float x = lm.getFloat(0) * width;
            float y = lm.getFloat(1) * height;
            mpLandmarks.add(new PVector(x, y));
          }
        }
      }
    } catch (Exception e) {
      println("Error reading MediaPipe: " + e.getMessage());
    }
  }
}

// ===== Draw gesture info =====
void drawGestureInfo(HandData hand, int gestureId) {
  fill(0, 150);
  noStroke();
  rect(10, height - 60, 200, 40);
  fill(255);
  textSize(16);
  textAlign(LEFT);
  String gestureText = (gestureId >= 0 && gestureId < gesture_labels.length) ? gesture_labels[gestureId] : "Unknown";
  text("Gesture: " + gestureText, 20, height - 30);
}

// ===== Point history =====
void updatePointHistory(HandData hand) {
  if (hand.landmarks.size() > 8) {
    PVector indexTip = hand.landmarks.get(8);
    point_history.add(indexTip.copy());
    while (point_history.size() > history_length) point_history.remove(0);
  }
}

void drawPointHistory() {
  if (point_history.size() < 2) return;
  for (int i = 1; i < point_history.size(); i++) {
    PVector p1 = point_history.get(i-1);
    PVector p2 = point_history.get(i);
    float alpha = map(i, 0, point_history.size(), 50, 255);
    stroke(255, 100, 100, alpha);
    strokeWeight(map(i, 0, point_history.size(), 1, 4));
    line(p1.x, p1.y, p2.x, p2.y);
  }
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
  ArrayList<PVector> landmarks;
  HandData() { landmarks = new ArrayList<PVector>(); }
}

// ===== Gesture classifier =====
class HandGestureClassifier {
  public int classify(HandData hand) {
    if (hand.landmarks == null || hand.landmarks.size() < 21) return -1;

    PVector wrist = hand.landmarks.get(0);
    PVector thumbTip = hand.landmarks.get(4);
    PVector indexTip = hand.landmarks.get(8);
    PVector middleTip = hand.landmarks.get(12);
    PVector ringTip = hand.landmarks.get(16);
    PVector pinkyTip = hand.landmarks.get(20);

    float dThumb = dist(wrist.x, wrist.y, thumbTip.x, thumbTip.y);
    float dIndex = dist(wrist.x, wrist.y, indexTip.x, indexTip.y);
    float dMiddle = dist(wrist.x, wrist.y, middleTip.x, middleTip.y);
    float dRing = dist(wrist.x, wrist.y, ringTip.x, ringTip.y);
    float dPinky = dist(wrist.x, wrist.y, pinkyTip.x, pinkyTip.y);

    float avg = (dIndex + dMiddle + dRing + dPinky) / 4.0;

    boolean thumbOpen  = dThumb  > avg * 0.5;
    boolean indexOpen  = dIndex  > avg * 0.5;
    boolean middleOpen = dMiddle > avg * 0.5;
    boolean ringOpen   = dRing   > avg * 0.5;
    boolean pinkyOpen  = dPinky  > avg * 0.5;

    if (indexOpen && middleOpen && ringOpen && pinkyOpen) return 0; // Open !
    else if (indexOpen && middleOpen && !ringOpen && pinkyOpen) return 1; // Three !
    else if (indexOpen && middleOpen && ringOpen && !pinkyOpen) return 2; // Point
    else if (indexOpen && middleOpen && !ringOpen && !pinkyOpen) return 3; // Peace !
    else if (indexOpen && !middleOpen && !ringOpen && pinkyOpen) return 4; // OK !
    else if (pinkyOpen && thumbOpen && !indexOpen && !middleOpen && !ringOpen) return 5; // Call +-

    return -1;
  }
}
