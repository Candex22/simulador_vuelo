import java.net.*;
import java.io.*;
import java.util.*;
import processing.data.*;

// ===================== Red / MediaPipe =====================
Socket socket;
BufferedReader input;

ArrayList<HandData> mpHands = new ArrayList<HandData>();
HandGestureClassifier handClassifier = new HandGestureClassifier();


// Two-hand control state
int leftHandGesture = -1;
int rightHandGesture = -1;
int lastValidLeftGesture = -1;
int lastValidRightGesture = -1;
int framesWithoutDetection = 0;
int maxFramesWithoutDetection = 1; // Tolerancia de ~10 frames sin detección
String controlStatus = "Sin control";
int gameState = 0; // 0=Inicio, 1=Volando, 2=Pausado
boolean waitingForGestureRelease = false;
int peaceGestureFrameCount = 0;  // NUEVO
int requiredPeaceFrames = 15;     // NUEVO - frames necesarios para activar
boolean lastFrameWasPeace = false; // NUEVO

// FPS simple para debug
int fps = 0;
int lastTime = 0;
int frameCountFPS = 0;

// ===================== Terreno (tu código) =====================
import java.util.ArrayList;
import java.util.HashMap;
PGraphics horizonteBuffer;
PGraphics mascaraHorizonte;

// ===================== Cámara =====================
float camX = 0, camY = 300, camZ = 0;
float currentSpeed = 0.5;        // era 1
float maxSpeed = 8;              // era 20
float currentMaxSpeed = 8;       // era 20
float maxSpeedStep = 2;          // era 5
float acceleration = 0.2;        // era 0.5
float deceleration = 0.1; 
float yaw = 0, pitch = 0, roll = 0;
float sensitivity = 0.005;
float cameraGroundOffset = 5;
PVector velocity = new PVector(0,0,0);
float damping = 0.99; 

// Teclas
boolean moveForward = false, moveBackward = false;
boolean moveLeft = false, moveRight = false;
boolean moveUp = false, moveDown = false;
boolean accelerate = false, decelerate = false;
boolean speedUp = false, speedDown = false;

// ===================== Mundo =====================
int chunkSize = 500;
int worldSize = 2000;
int seed = 12345;

HashMap<String, ArrayList<PVector>> cloudsPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, Boolean> cloudsGeneratedForChunk = new HashMap<String, Boolean>();
HashMap<String, ArrayList<PVector>> treesPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, ArrayList<PVector>> buildingsPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, Integer> chunkTypes = new HashMap<String, Integer>();
HashMap<String, Boolean> airportPerChunk = new HashMap<String, Boolean>();

float gridSize = 40;
float noiseScale = 0.01;
float terrainHeightScale = 22;
float mountainHeightScale = 160;

final float MAX_WORLD_HEIGHT = 1000;

// Ciudad
float cityBaseY = 11;
float roadWidth = 40;
float sidewalkWidth = 10;
float sidewalkHeight = 0.1;

// Hitboxes edificios
class AABB {
  float minX, minY, minZ, maxX, maxY, maxZ;
  AABB(float minX, float minY, float minZ, float maxX, float maxY, float maxZ){
    this.minX=minX; this.minY=minY; this.minZ=minZ;
    this.maxX=maxX; this.maxY=maxY; this.maxZ=maxZ;
  }
  boolean contains(float x, float y, float z){
    return (x>=minX && x<=maxX && y>=minY && y<=maxY && z>=minZ && z<=maxZ);
  }
}
HashMap<String, ArrayList<AABB>> aabbsPerChunk = new HashMap<String, ArrayList<AABB>>();

// Nubes
ArrayList<PVector> clouds = new ArrayList<PVector>();
int cloudCount = 60;
float cloudY = 260;

// ===================== HUD (overlay 2D) =====================
float hudSpeed = 0;
float prevX, prevY, prevZ;
int prevT = 0;

// ===================== Util =====================
String keyOf(int cx, int cz){ return cx + "," + cz; }

float hash2i(int x, int y){
  int h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  h ^= (h >> 16);
  return (h & 0x7fffffff) / (float)0x80000000;
}

float smoothstep(float a, float b, float x){
  x = constrain((x-a)/(b-a), 0, 1);
  return x*x*(3-2*x);
}

float length2(float x, float z){ return sqrt(x*x+z*z); }

String lastControlStatus = "";


// ===================== Setup/Draw =====================
void setup(){
  size(800, 600, P3D);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
  noiseSeed(seed);
  
  horizonteBuffer = createGraphics(120, 120, P2D);
  mascaraHorizonte = createGraphics(120, 120, P2D);

  mascaraHorizonte.beginDraw();
  mascaraHorizonte.background(0);
  mascaraHorizonte.noStroke();
  mascaraHorizonte.fill(255);
  mascaraHorizonte.ellipse(60, 60, 120, 120);
  mascaraHorizonte.endDraw();

  // ===== Conexión a Python MediaPipe =====
  try {
    socket = new Socket("127.0.0.1", 5005);
    input = new BufferedReader(new InputStreamReader(socket.getInputStream()));
    println("Conectado a MediaPipe Python en 127.0.0.1:5005");
  } catch (Exception e) {
    println("No se pudo conectar al servidor Python: " + e.getMessage());
  }
}

void draw(){
  background(135,206,235);

  // ---- 1) Leer landmarks de ambas manos + clasificar gestos + aplicar controles ----
  readMediaPipeHands();
  leftHandGesture = -1;
  rightHandGesture = -1;
  
  // Classify gestures for each hand
  for (HandData hand : mpHands) {
    if (hand.landmarks.size() == 21) {
      int gestureId = handClassifier.classifySimple(hand);
      if (hand.label.equals("Left")) {
        leftHandGesture = gestureId;
      } else if (hand.label.equals("Right")) {
        rightHandGesture = gestureId;
      }
    }
  }
  
  applyTwoHandControl();

  // ---- 2) Mundo 3D (tu ciclo original) ----
  // SOLO actualizar cámara si NO estamos pausados
  if (gameState == 1) {
    updateCamera();
  }
  
  applyCamera();

  int chunkX = floor(camX / chunkSize);
  int chunkZ = floor(camZ / chunkSize);
  int viewRange = 2;

  // Nubes: limpiar chunks fuera de vista
  ArrayList<String> visibleChunks = new ArrayList<String>();
  for (int dx=-viewRange; dx<=viewRange; dx++){
    for (int dz=-viewRange; dz<=viewRange; dz++){
      visibleChunks.add(keyOf(chunkX + dx, chunkZ + dz));
    }
  }

  ArrayList<String> keysToRemove = new ArrayList<String>();
  for (String k : cloudsPerChunk.keySet()){
    if (!visibleChunks.contains(k)){
      for (PVector c : cloudsPerChunk.get(k)){
        clouds.remove(c);
      }
      keysToRemove.add(k);
    }
  }
  for (String k : keysToRemove){
    cloudsPerChunk.remove(k);
  }

  // Terreno + contenido
  for (int dx = -viewRange; dx <= viewRange; dx++){
    for (int dz = -viewRange; dz <= viewRange; dz++){
      int ncx = chunkX + dx;
      int ncz = chunkZ + dz;

      generateCloudsForChunk(ncx, ncz);
      drawChunk(ncx, ncz);
    }
  }

  drawClouds();

  // ====== HUD + overlays 2D ======
  updateHUDData();
  drawHUD();
  drawGestureOverlay();
  drawFPS();
  
  // Dibujar overlays según el estado
  if (gameState == 0) {
    drawStartScreen();
  } else if (gameState == 2) {
    drawPauseScreen();
  }
  
  calculateFPS();
}

// ===================== Integración con gestos =====================
void applyTwoHandControl() {
  boolean leftValid = (leftHandGesture == 0 || leftHandGesture == 1 || leftHandGesture == 2);
  boolean rightValid = (rightHandGesture == 0 || rightHandGesture == 1 || rightHandGesture == 2);
  
  // Ambas manos en paz - toggle pause/play
  boolean bothPeace = (leftHandGesture == 2 && rightHandGesture == 2);
  
  if (gameState == 0) {
    // INICIO
    if (bothPeace) {
      gameState = 1;
      waitingForGestureRelease = true;
      controlStatus = "¡INICIANDO VUELO!";
    } else {
      controlStatus = "Haz ✌️ con ambas manos para iniciar";
    }
    return;
  } else if (gameState == 1) {
    // VOLANDO
    if (bothPeace && !waitingForGestureRelease) {
      gameState = 2;
      waitingForGestureRelease = true;
      controlStatus = "PAUSADO";
      moveForward = false;
      moveBackward = false;
      moveLeft = false;
      moveRight = false;
      return;
    }
    
    if (!bothPeace && waitingForGestureRelease) {
      waitingForGestureRelease = false;
    }
    
    if (waitingForGestureRelease) {
      return;
    }
  } else if (gameState == 2) {
    // PAUSADO
    if (bothPeace && !waitingForGestureRelease) {
      gameState = 1;
      waitingForGestureRelease = true;
      controlStatus = "¡REANUDANDO VUELO!";
    } else {
      if (!bothPeace && waitingForGestureRelease) {
        waitingForGestureRelease = false;
      }
      controlStatus = "PAUSADO - Haz ✌️ con ambas manos para continuar";
    }
    return;
  }
  
  // Controles normales de vuelo
  if (!leftValid || !rightValid) {
    framesWithoutDetection++;
    if (framesWithoutDetection > maxFramesWithoutDetection) {
      String newStatus = "Sin control detectado";
      if (!newStatus.equals(lastControlStatus)) {
        controlStatus = newStatus;
        lastControlStatus = newStatus;
        moveForward = false;
        moveBackward = false;
        moveLeft = false;
        moveRight = false;
      }
    }
    return;
  }
  
  framesWithoutDetection = 0;
  
  // UNA mano en paz = vuelo recto
  if ((leftHandGesture == 2 && rightHandGesture != 2) || 
      (rightHandGesture == 2 && leftHandGesture != 2)) {
    String newStatus = "Vuelo recto (Una mano en paz ✌️)";
    if (!newStatus.equals(lastControlStatus)) {
      controlStatus = newStatus;
      lastControlStatus = newStatus;
    }
    moveForward = false;
    moveBackward = false;
    moveLeft = false;
    moveRight = false;
    return;
  }
  
  String newStatus = "Vuelo recto";
  boolean newMoveForward = false;
  boolean newMoveBackward = false;
  boolean newMoveLeft = false;
  boolean newMoveRight = false;
  
  // Ambas abiertas (0) - Pitch up
  if (leftHandGesture == 0 && rightHandGesture == 0) {
    newStatus = "Cabeceo ARRIBA ↑";
    newMoveBackward = true;
  }
  // Ambos puños (1) - Pitch down
  else if (leftHandGesture == 1 && rightHandGesture == 1) {
    newStatus = "Cabeceo ABAJO ↓";
    newMoveForward = true;
  }
  // Derecha abierta + Izquierda puño - Turn right
  else if (rightHandGesture == 0 && leftHandGesture == 1) {
    newStatus = "Giro IZQUIERDA ←";
    newMoveRight = true;
  }
  // Izquierda abierta + Derecha puño - Turn left
  else if (leftHandGesture == 0 && rightHandGesture == 1) {
    newStatus = "Giro DERECHA →";
    newMoveLeft = true;
  }
  
  if (!newStatus.equals(lastControlStatus)) {
    controlStatus = newStatus;
    lastControlStatus = newStatus;
  }
  
  moveForward = newMoveForward;
  moveBackward = newMoveBackward;
  moveLeft = newMoveLeft;
  moveRight = newMoveRight;
}

// ===== Leer manos desde Python =====
void readMediaPipeHands() {
  mpHands.clear();
  if (input == null) return;
  try {
    if (input.ready()) {
      String line = input.readLine();
      if (line != null && line.length() > 0) {
        JSONArray handsArray = parseJSONArray(line);
        if (handsArray != null) {
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
            
            mpHands.add(hand);
          }
        }
      }
    }
  } catch (Exception e) {
    println("Error leyendo MediaPipe: " + e.getMessage());
  }
}

// ===== Dibujo overlay del gesto =====
void drawGestureOverlay(){
  hint(DISABLE_DEPTH_TEST);
  noLights();
  camera();
  ortho();

  fill(0, 180);
  noStroke();
  rect(10, 10, 280, 90, 8);
  
  fill(255);
  textAlign(LEFT, TOP);
  textSize(14);
  text("Control:", 20, 20);
  
  textSize(18);
  fill(0, 255, 100);
  text(controlStatus, 20, 45);
  
  textSize(12);
  fill(200);
  text("Izq: " + getGestureName(leftHandGesture), 20, 70);
  text("Der: " + getGestureName(rightHandGesture), 150, 70);

  hint(ENABLE_DEPTH_TEST);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
}

String getGestureName(int gestureId) {
  if (gestureId == 0) return "Abierto";
  if (gestureId == 1) return "Puño";
  if (gestureId == 2) return "Paz ✌️";
  return "---";
}

// ===== FPS =====
void calculateFPS() {
  frameCountFPS++;
  if (millis() - lastTime > 1000) {
    fps = frameCountFPS;
    frameCountFPS = 0;
    lastTime = millis();
  }
}

void drawFPS() {
  hint(DISABLE_DEPTH_TEST);
  noLights();
  camera();
  ortho();
  fill(255);
  textSize(12);
  textAlign(RIGHT, TOP);
  text("FPS: " + fps, width-10, 10);
  hint(ENABLE_DEPTH_TEST);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
}

// ===================== Cámara =====================
void updateCamera() {
  // 1. ROTACIÓN
  if (moveLeft)  yaw -= 0.05;
  if (moveRight) yaw += 0.05;
  if (moveForward)   pitch -= 0.02;
  if (moveBackward)  pitch += 0.02;
  pitch = constrain(pitch, -PI/2 + 0.1, PI/2 - 0.1);

  float targetRoll = 0;
  if (moveRight) targetRoll = -PI/8;
  if (moveLeft)  targetRoll =  PI/8;
  roll = lerp(roll, targetRoll, 0.1);

  // 2. CONTROL DE VELOCIDAD
  if (speedUp)  currentSpeed += acceleration;
  if (speedDown)  currentSpeed -= acceleration;
  currentSpeed = constrain(currentSpeed, 0, currentMaxSpeed);

  // 3. DIRECCIÓN COMPLETA
  PVector lookDir = new PVector(
    cos(pitch) * cos(yaw),
    sin(pitch),
    cos(pitch) * sin(yaw)
  );

  lookDir.normalize();
  PVector movement = PVector.mult(lookDir, currentSpeed);

  // 4. AMORTIGUACIÓN
  velocity.x += movement.x;
  velocity.z += movement.z;
  velocity.mult(damping);
  if (velocity.mag() > maxSpeed) velocity.normalize().mult(maxSpeed);

  // 5. APLICAR MOVIMIENTO
  camX += velocity.x;
  camY += movement.y;
  camZ += velocity.z;

  // 6. LÍMITES Y COLISIÓN
  float groundY = getTerrainHeight(camX, camZ);
  if (camY < groundY + cameraGroundOffset) camY = groundY + cameraGroundOffset;
  if (camY > 1200) camY = 1200;

  resolveBuildingCollision();
}

void applyCamera(){
  float lookX = cos(yaw) * cos(pitch);
  float lookY = sin(pitch);
  float lookZ = sin(yaw) * cos(pitch);
  
  PVector look = new PVector(lookX, lookY, lookZ);
  PVector right = new PVector(cos(yaw + PI/2.0), 0, sin(yaw + PI/2.0));
  PVector up = PVector.cross(look, right, null);

  PVector rolledUp = new PVector();
  float cosRoll = cos(roll);
  float sinRoll = sin(roll);
  rolledUp.x = cosRoll * up.x + sinRoll * right.x;
  rolledUp.y = cosRoll * up.y + sinRoll * right.y;
  rolledUp.z = cosRoll * up.z + sinRoll * right.z;

  camera(camX, camY, camZ, camX + look.x, camY + look.y, camZ + look.z, rolledUp.x, rolledUp.y, rolledUp.z);
  directionalLight(255, 255, 255, 0, -1, 0);
}

// ===================== Biomas y alturas =====================
int getChunkType(int cx, int cz){
  String k = keyOf(cx,cz);
  if (isAirportChunk(cx, cz)) {
    chunkTypes.put(k, 3);
    return 3;
  }
  if (chunkTypes.containsKey(k)) return chunkTypes.get(k);
  float r = 0.65*noise((cx+seed)*0.17, (cz-seed)*0.17) + 0.35*hash2i(cx,cz);
  int type;
  if (r > 0.78)      type = 2;
  else if (r > 0.10) type = 1;
  else               type = 0;
  if (type == 2){
    int[][] nbs = {{1,0},{-1,0},{0,1},{0,-1}};
    for (int i=0;i<nbs.length;i++){
      int nx=cx+nbs[i][0], nz=cz+nbs[i][1];
      String nk = keyOf(nx,nz);
      if (isAirportChunk(nx, nz)) {
        chunkTypes.put(nk, 3);
        continue;
      }
      if (!chunkTypes.containsKey(nk)){
        float rr = 0.65*noise((nx+seed)*0.17, (nz-seed)*0.17) + 0.35*hash2i(nx,nz);
        int t2 = (rr > 0.78) ? 2 : 0;
        chunkTypes.put(nk, t2);
      } else {
        int cur = chunkTypes.get(nk);
        if (cur == 1) chunkTypes.put(nk, 0);
      }
    }
  }
  chunkTypes.put(k, type);
  return type;
}

float getTerrainHeight(float x, float z){
  int cx = floor(x / chunkSize);
  int cz = floor(z / chunkSize);
  int ct = getChunkType(cx, cz);

  if (ct == 3){
    return cityBaseY;
  } else if (ct == 1){
    return cityBaseY;
  } else if (ct == 2){
    float centerX = cx*chunkSize + chunkSize*0.5;
    float centerZ = cz*chunkSize + chunkSize*0.5;
    float d = dist(x, z, centerX, centerZ);
    float r0 = chunkSize*0.42;
    float r1 = chunkSize*0.52;
    float mask = 1.0 - smoothstep(r0, r1, d);
    float base = noise(x*noiseScale + seed*100, z*noiseScale + seed*100) * terrainHeightScale * 0.55;
    float peak = noise(x*noiseScale*0.6 + 999, z*noiseScale*0.6 + 999) * mountainHeightScale;
    float h = base + peak * mask + 8*mask;
    return h;
  } else {
    return noise(x*noiseScale + seed*100, z*noiseScale + seed*100) * terrainHeightScale;
  }
}

boolean isRoadLocal(float localX, float localZ){
  for (int rx = 0; rx <= chunkSize; rx += 200){
    if (abs(localX - rx) < (roadWidth/2 + sidewalkWidth + 5)) return true;
  }
  for (int rz = 0; rz <= chunkSize; rz += 200){
    if (abs(localZ - rz) < (roadWidth/2 + sidewalkWidth + 5)) return true;
  }
  return false;
}

boolean isInsideBuildingFootprint(float localX, float localZ){
  for (int i = 100; i < chunkSize; i += 200){
    for (int j = 100; j < chunkSize; j += 200){
      float cx = i + 10 + 30;
      float cz = j + 10 + 30;
      if (abs(localX - cx) < 35 && abs(localZ - cz) < 35) return true;
    }
  }
  return false;
}

// ===================== Dibujo de chunk =====================
void drawChunk(int cx, int cz){
  float baseX = cx * chunkSize;
  float baseZ = cz * chunkSize;
  String key = keyOf(cx, cz);
  int type = getChunkType(cx, cz);

  drawTerrain(baseX, baseZ, type);

  if (type == 0) {
    drawPradera(baseX, baseZ, key, type);
  } else if (type == 1) {
    drawCiudad(baseX, baseZ, key);
  } else if (type == 3) {
    drawAirport(baseX, baseZ);
  }
}

boolean isAirportChunk(int cx, int cz){
  return ( (cx == 0 && abs(cz) % 100 == 0) || (cz == 0 && abs(cx) % 100 == 0) );
}

void drawAirport(float baseX, float baseZ){ 
  float y = getTerrainHeight(baseX+chunkSize/2, baseZ+chunkSize/2); 
  
  pushMatrix(); 
  translate(baseX + chunkSize/2, y+1, baseZ + chunkSize/2); 
  fill(50); 
  box(chunkSize*0.8, 2, 100);
  popMatrix(); 
  
  pushMatrix(); 
  translate(baseX + chunkSize/2 - 50, y+50, baseZ + chunkSize/4); 
  fill(120,120,160); 
  box(40,100,40); 
  popMatrix();
  
  pushMatrix(); 
  translate(baseX + chunkSize/2 + 100, y+25, baseZ + chunkSize/2); 
  fill(150,80,80); 
  box(120,50,120); 
  popMatrix(); 
}

void generateCloudsForChunk(int cx, int cz){
  String key = keyOf(cx, cz);
  if (cloudsPerChunk.containsKey(key)) return;

  float cloudY_low = 500;
  float cloudY_high = 900;

  int cloudsCount_low = 8 + (int)random(0,1);
  ArrayList<PVector> localClouds = new ArrayList<PVector>();
  for(int i=0; i<cloudsCount_low; i++){
    float x = cx*chunkSize + random(0, chunkSize);
    float z = cz*chunkSize + random(0, chunkSize);
    float y = cloudY_low + random(-10,10);
    PVector c = new PVector(x,y,z);
    clouds.add(c);
    localClouds.add(c);
  }

  int cloudsCount_high = 8 + (int)random(0,1);
  for(int i=0; i<cloudsCount_high; i++){
    float x = cx*chunkSize + random(0, chunkSize);
    float z = cz*chunkSize + random(0, chunkSize);
    float y = cloudY_high + random(-10,10);
    PVector c = new PVector(x,y,z);
    clouds.add(c);
    localClouds.add(c);
  }

  cloudsPerChunk.put(key, localClouds);
}

void drawTerrain(float baseX, float baseZ, int type){
  if (type == 2) fill(139,137,137);
  else if (type == 1) fill(80, 120, 80);
  else if (type == 3) fill(90, 110, 90);
  else fill(34,139,34);

  stroke(0,80,0,50);
  for (float x = baseX; x < baseX + chunkSize; x += gridSize){
    for (float z = baseZ; z < baseZ + chunkSize; z += gridSize){
      float y1 = getTerrainHeight(x, z);
      float y2 = getTerrainHeight(x + gridSize, z);
      float y3 = getTerrainHeight(x + gridSize, z + gridSize);
      float y4 = getTerrainHeight(x, z + gridSize);
      beginShape(QUADS);
      vertex(x,           y1, z);
      vertex(x+gridSize,  y2, z);
      vertex(x+gridSize,  y3, z+gridSize);
      vertex(x,           y4, z+gridSize);
      endShape();
    }
  }
  noStroke();
}

void drawPradera(float baseX, float baseZ, String chunkKey, int chunkType){
  ArrayList<PVector> trees;
  if (treesPerChunk.containsKey(chunkKey)){
    trees = treesPerChunk.get(chunkKey);
  } else {
    trees = new ArrayList<PVector>();
    int attempts = 0, maxAttempts = 120;
    while (trees.size() < 10 && attempts < maxAttempts){
      float x = baseX + random(0, chunkSize);
      float z = baseZ + random(0, chunkSize);
      float y = getTerrainHeight(x, z);
    
      float lx = x - baseX;
      float lz = z - baseZ;
      if (isRoadLocal(lx, lz) || isInsideBuildingFootprint(lx, lz)){
        attempts++; continue;
      }
    
      int cx = floor(x / chunkSize);
      int cz = floor(z / chunkSize);
      String k = keyOf(cx, cz);
      if (aabbsPerChunk.containsKey(k)){
        boolean collision = false;
        for (AABB box : aabbsPerChunk.get(k)){
          if (y + 40 > box.minY && y < box.maxY){
            collision = true; break;
          }
        }
        if (collision){ attempts++; continue; }
      }
      trees.add(new PVector(x, y, z));
      attempts++;
    }
    treesPerChunk.put(chunkKey, trees);
  }

  for (PVector t : trees){
    pushMatrix();
    translate(t.x, t.y, t.z);
    fill(139,69,19);
    box(10, 40, 10);
    translate(0, 40, 0);
    fill(0,128,0);
    sphere(25);
    popMatrix();
  }
}

void drawCiudad(float baseX, float baseZ, String chunkKey){
  ArrayList<PVector> buildings;
  ArrayList<AABB> aabbs;

  if (buildingsPerChunk.containsKey(chunkKey)){
    buildings = buildingsPerChunk.get(chunkKey);
    aabbs = aabbsPerChunk.get(chunkKey);
  } else {
    buildings = new ArrayList<PVector>();
    aabbs = new ArrayList<AABB>();

    for (int i = 100; i < chunkSize; i += 200){
      for (int j = 100; j < chunkSize; j += 200){
        float lx = i + 10 + 30;
        float lz = j + 10 + 30;
        float x = baseX + lx;
        float z = baseZ + lz;
        float y = cityBaseY;

        buildings.add(new PVector(x, y, z));

        float h = 110 + (int)(noise(x * 0.01, z * 0.01) * 70);
        AABB box = new AABB(
          x - 30, y, z - 30,
          x + 30, y + h, z + 30
        );
        aabbs.add(box);
      }
    }
    buildingsPerChunk.put(chunkKey, buildings);
    aabbsPerChunk.put(chunkKey, aabbs);
  }

  float yRoad = cityBaseY + 1;

  // Verticales
  fill(40, 40, 40);
  for (int rx = 0; rx <= chunkSize; rx += 200){
    fill(40, 40, 40);
    pushMatrix();
    translate(baseX + rx, yRoad, baseZ + chunkSize/2);
    box(roadWidth, 1, chunkSize);
    popMatrix();

    fill(150);
    pushMatrix();
    translate(baseX + rx - roadWidth/2 - sidewalkWidth/2, yRoad + sidewalkHeight/2, baseZ + chunkSize/2);
    box(sidewalkWidth, sidewalkHeight, chunkSize);
    popMatrix();
    pushMatrix();
    translate(baseX + rx + roadWidth/2 + sidewalkWidth/2, yRoad + sidewalkHeight/2, baseZ + chunkSize/2);
    box(sidewalkWidth, sidewalkHeight, chunkSize);
    popMatrix();

    for (float z = 0; z < chunkSize; z += 40){
      fill(255,255,0);
      pushMatrix();
      translate(baseX + rx, yRoad + 0.7, baseZ + z + 10);
      box(4, 0.2, 20);
      popMatrix();
    }
  }

  // Horizontales
  fill(40, 40, 40);
  for (int rz = 0; rz <= chunkSize; rz += 200){
    fill(40, 40, 40);
    pushMatrix();
    translate(baseX + chunkSize/2, yRoad, baseZ + rz);
    box(chunkSize, 1, roadWidth);
    popMatrix();

    fill(150);
    pushMatrix();
    translate(baseX + chunkSize/2, yRoad + sidewalkHeight/2, baseZ + rz - roadWidth/2 - sidewalkWidth/2);
    box(chunkSize, sidewalkHeight, sidewalkWidth);
    popMatrix();
    pushMatrix();
    translate(baseX + chunkSize/2, yRoad + sidewalkHeight/2, baseZ + rz + roadWidth/2 + sidewalkWidth/2);
    box(chunkSize, sidewalkHeight, sidewalkWidth);
    popMatrix();

    for (float x = 0; x < chunkSize; x += 40){
      fill(255, 255, 0);
      pushMatrix();
      translate(baseX + x + 10, yRoad + 0.7, baseZ + rz);
      box(20, 0.2, 4);
      popMatrix();
    }
  }

  // Edificios
  for (int i=0; i<buildings.size(); i++){
    PVector b = buildings.get(i);
    float h = 110 + (int)(noise(b.x * 0.01, b.z * 0.01) * 70);
    float distToCam = dist(b.x, b.z, camX, camZ);
    boolean near = distToCam < 80;

    pushMatrix();
    translate(b.x, b.y + h/2.0, b.z);
  
    if (near){
      fill(100, 180);
    } else {
      fill(100);
    }
    box(60, h, 60);
    popMatrix();
  }
}

// ===================== Colisión edificios =====================
void resolveBuildingCollision(){
  int cx = floor(camX / chunkSize);
  int cz = floor(camZ / chunkSize);
  for (int dx=-1; dx<=1; dx++){
    for (int dz=-1; dz<=1; dz++){
      String k = keyOf(cx+dx, cz+dz);
      if (!aabbsPerChunk.containsKey(k)) continue;
      ArrayList<AABB> list = aabbsPerChunk.get(k);
      for (AABB box : list){
        if (box.contains(camX, camY, camZ)){
          float pushX = min(abs(camX - box.minX), abs(box.maxX - camX));
          float pushZ = min(abs(camZ - box.minZ), abs(box.maxZ - camZ));
          if (pushX < pushZ){
            if (abs(camX - box.minX) < abs(box.maxX - camX)) camX = box.minX - 0.2;
            else camX = box.maxX + 0.2;
          } else {
            if (abs(camZ - box.minZ) < abs(box.maxZ - camZ)) camZ = box.minZ - 0.2;
            else camZ = box.maxZ + 0.2;
          }
        }
      }
    }
  }
}

// ===================== Nubes =====================
void drawClouds(){ 
  noStroke(); 
  fill(255, 255, 255, 220);
  for (PVector c : clouds){ 
    float d = dist(camX, camZ, c.x, c.z); 
    float s = map(d, 0, 1200, 120, 40);
    pushMatrix(); 
    translate(c.x, c.y, c.z); 
    float ang = atan2(camX - c.x, camZ - c.z); 
    rotateY(ang); 
    noLights(); 
    noStroke(); 
    fill(255, 255, 255, 100); 
    beginShape(QUADS); 
    vertex(-s,  25, 0); 
    vertex( s,  25, 0); 
    vertex( s, -25, 0); 
    vertex(-s, -25, 0); 
    endShape(); 
    lights(); 
    popMatrix(); 
  } 
}

// ===================== HUD =====================
void updateHUDData(){
  int t = millis();
  if (prevT == 0){
    prevX = camX; prevY = camY; prevZ = camZ; prevT = t; hudSpeed = 0;
    return;
  }
  float dt = max(1, t - prevT) / 1000.0;
  float dx = camX - prevX;
  float dy = camY - prevY;
  float dz = camZ - prevZ;
  float d = sqrt(dx*dx + dy*dy + dz*dz);
  hudSpeed = d / dt;
  prevX = camX; prevY = camY; prevZ = camZ; prevT = t;
}

void drawHUD(){
  hint(DISABLE_DEPTH_TEST);
  noLights();
  camera();
  ortho();

  pushStyle();
  noStroke();
  fill(0, 120);
  rect(0, height-160, width, 160);

  // Horizonte artificial
  pushMatrix();
  translate(width*0.22, height-80);

  horizonteBuffer.beginDraw();
  horizonteBuffer.background(0, 0);
  horizonteBuffer.translate(60, 60);
  horizonteBuffer.noStroke();

  horizonteBuffer.pushMatrix();
  horizonteBuffer.translate(0, map(pitch, -PI/4, PI/4, -40, 40));
  horizonteBuffer.rotate(-roll);

  horizonteBuffer.fill(70,130,180);
  horizonteBuffer.rect(-200, -200, 400, 200);

  horizonteBuffer.fill(139,69,19);
  horizonteBuffer.rect(-200, 0, 400, 200);

  horizonteBuffer.stroke(0);
  horizonteBuffer.strokeWeight(1.5);
  horizonteBuffer.line(-400, 0, 400, 0);
  horizonteBuffer.popMatrix();

  horizonteBuffer.endDraw();

  PImage hImg = horizonteBuffer.get();
  hImg.mask(mascaraHorizonte.get());
  image(hImg, -60, -60);

  noFill();
  stroke(255);
  strokeWeight(3);
  ellipse(0, 0, 120, 120);

  stroke(255,120,0);
  strokeWeight(3);
  line(-30, 0, 30, 0);
  line(0, -10, 0, 10);

  fill(255);
  noStroke();
  textAlign(CENTER, CENTER);
  textSize(12);
  text("HORIZONTE", 0, 70);

  popMatrix();

  // Altímetro
  pushMatrix();
  translate(width*0.44, height-80);
  stroke(255);
  noFill();
  rectMode(CENTER);
  rect(0,0,120,60,10);
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(12);
  text("ALTURA", 0, -40);
  textSize(16);
  text(nf(camY,0,1)+" m", 0, 0);
  popMatrix();

  // Velocímetro
  pushMatrix();
  translate(width*0.60, height-80);
  stroke(255);
  noFill();
  rectMode(CENTER);
  rect(0,0,120,60,10);
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(12);
  text("VELOCIDAD", 0, -40);
  textSize(16);
  text(nf(hudSpeed,0,1)+" u/s", 0, 0);
  popMatrix();

  // Rumbo
  pushMatrix();
  translate(width*0.80, height-80);
  stroke(255);
  noFill();
  ellipse(0,0,120,120);
  stroke(255,0,0);
  line(0,0,0,-50);
  float heading = (degrees(yaw) % 360 + 360) % 360;
  fill(255);
  noStroke();
  textAlign(CENTER, CENTER);
  textSize(12);
  text("RUMBO", 0, -60);
  textSize(16);
  text(int(heading) + "°", 0, 60);
  popMatrix();

  popStyle();
  
  if (camY >= 1000) {
    pushStyle();
    textAlign(CENTER, CENTER);
    textSize(24);
    fill(255, 0, 0);
    text("ADVERTENCIA: Límite de altura próximo (1200m)", width/2, 50);
    popStyle();
  }

  // Encuadre negro
  pushStyle();
  rectMode(CORNER);
  noStroke();
  fill(0);

  float marginX = width * 0.03;
  float marginY = height * 0.03;

  rect(0, 0, width, marginY);
  rect(0, height - marginY, width, marginY);
  rect(0, marginY, marginX, height - 2*marginY);
  rect(width - marginX, marginY, marginX, height - 2*marginY);

  popStyle();

  hint(ENABLE_DEPTH_TEST);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
}
void drawStartScreen() {
  hint(DISABLE_DEPTH_TEST);
  noLights();
  camera();
  ortho();
  
  fill(0, 220);
  noStroke();
  rect(0, 0, width, height);
  
  fill(0, 255, 100);
  textAlign(CENTER, CENTER);
  textSize(48);
  text("SIMULADOR DE VUELO", width/2, height/2 - 100);
  
  fill(255);
  textSize(32);
  text("✌️ Haz el símbolo de PAZ ✌️", width/2, height/2);
  text("con ambas manos para iniciar", width/2, height/2 + 40);
  
  textSize(20);
  fill(200);
  text("Controles:", width/2, height/2 + 120);
  textSize(16);
  text("Ambas abiertas = Cabeceo arriba", width/2, height/2 + 150);
  text("Ambos puños = Cabeceo abajo", width/2, height/2 + 175);
  text("Derecha abierta + Izq puño = Giro derecha", width/2, height/2 + 200);
  text("Izquierda abierta + Der puño = Giro izquierda", width/2, height/2 + 225);
  text("Una mano en paz = Vuelo recto", width/2, height/2 + 250);
  
  hint(ENABLE_DEPTH_TEST);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
}

void drawPauseScreen() {
  hint(DISABLE_DEPTH_TEST);
  noLights();
  camera();
  ortho();
  
  fill(0, 180);
  noStroke();
  rect(0, 0, width, height);
  
  fill(255, 200, 0);
  textAlign(CENTER, CENTER);
  textSize(64);
  text("|| PAUSADO ||", width/2, height/2 - 50);
  
  fill(255);
  textSize(28);
  text("✌️ Haz el símbolo de PAZ ✌️", width/2, height/2 + 30);
  text("con ambas manos para continuar", width/2, height/2 + 65);
  
  hint(ENABLE_DEPTH_TEST);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
}
// ===================== Teclado =====================
void keyPressed(){
  if (key == 'w' || key == 'W') moveForward = true;  
  if (key == 's' || key == 'S') moveBackward = true; 
  if (key == 'd' || key == 'D') moveLeft = true;
  if (key == 'a' || key == 'A') moveRight = true;
  if (key == 'r' || key == 'R') speedUp = true;
  if (key == 'f' || key == 'F') speedDown = true;
}

void keyReleased(){
  if (key == 'w' || key == 'W') moveForward = false;
  if (key == 's' || key == 'S') moveBackward = false;
  if (key == 'd' || key == 'D') moveLeft = false;
  if (key == 'a' || key == 'A') moveRight = false;
  if (key == 'r' || key == 'R') speedUp = false;
  if (key == 'f' || key == 'F') speedDown = false;
}

// ===================== Clases =====================
class HandData {
  String label;
  ArrayList<PVector> landmarks;
  HandData() { 
    label = "";
    landmarks = new ArrayList<PVector>(); 
  }
}

class HandGestureClassifier {
  public int classifySimple(HandData hand) {
    if (hand.landmarks == null || hand.landmarks.size() < 21) return -1;

    PVector wrist = hand.landmarks.get(0);
    
    PVector indexTip = hand.landmarks.get(8);
    PVector middleTip = hand.landmarks.get(12);
    PVector ringTip = hand.landmarks.get(16);
    PVector pinkyTip = hand.landmarks.get(20);
    
    PVector indexMCP = hand.landmarks.get(5);
    PVector middleMCP = hand.landmarks.get(9);
    PVector ringMCP = hand.landmarks.get(13);
    PVector pinkyMCP = hand.landmarks.get(17);

    float indexExtended = dist(indexMCP.x, indexMCP.y, indexTip.x, indexTip.y);
    float middleExtended = dist(middleMCP.x, middleMCP.y, middleTip.x, middleTip.y);
    float ringExtended = dist(ringMCP.x, ringMCP.y, ringTip.x, ringTip.y);
    float pinkyExtended = dist(pinkyMCP.x, pinkyMCP.y, pinkyTip.x, pinkyTip.y);
    
    float indexBase = dist(wrist.x, wrist.y, indexMCP.x, indexMCP.y);
    float middleBase = dist(wrist.x, wrist.y, middleMCP.x, middleMCP.y);
    float ringBase = dist(wrist.x, wrist.y, ringMCP.x, ringMCP.y);
    float pinkyBase = dist(wrist.x, wrist.y, pinkyMCP.x, pinkyMCP.y);
    
    float avgBase = (indexBase + middleBase + ringBase + pinkyBase) / 4.0;

    boolean indexOpen = indexExtended > avgBase * 0.7;
    boolean middleOpen = middleExtended > avgBase * 0.7;
    boolean ringOpen = ringExtended > avgBase * 0.7;
    boolean pinkyOpen = pinkyExtended > avgBase * 0.7;

    // GESTO DE PAZ: índice y medio extendidos, anular y meñique cerrados
    if (indexOpen && middleOpen && !ringOpen && !pinkyOpen) {
      return 2; // Paz ✌️
    }

    int openCount = 0;
    if (indexOpen) openCount++;
    if (middleOpen) openCount++;
    if (ringOpen) openCount++;
    if (pinkyOpen) openCount++;

    if (openCount >= 3) {
      return 0; // Open
    }
    
    if (openCount <= 1) {
      return 1; // Fist
    }

    return -1;
  }
}
