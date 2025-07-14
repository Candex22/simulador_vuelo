import java.util.ArrayList;
import java.util.HashMap;
// Cámara
float camX = 0, camY = 300, camZ = 0;
float camSpeed = 5;
float yaw = 0, pitch = 0;
float sensitivity = 0.005;
float cameraGroundOffset = 5;
// Movimiento
boolean moveForward = false, moveBackward = false;
boolean moveLeft = false, moveRight = false;
boolean moveUp = false, moveDown = false;
// Mundo
int chunkSize = 500;
int worldSize = 2000;
int seed = 0;
HashMap<String, ArrayList<PVector>> treesPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, ArrayList<PVector>> buildingsPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, Integer> chunkTypes = new HashMap<String, Integer>();
float gridSize = 40;
float noiseScale = 0.01;
float terrainHeightScale = 20; // terreno plano
float mountainHeightScale = 200; // para bioma montañoso
void setup() {
  size(800, 600, P3D);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
  noiseSeed(seed);
}
void draw() {
  background(135, 206, 235);
  updateCamera();
  applyCamera();
  int chunkX = floor(camX / chunkSize);
  int chunkZ = floor(camZ / chunkSize);
  int viewRange = 2;
  for (int dx = -viewRange; dx <= viewRange; dx++) {
    for (int dz = -viewRange; dz <= viewRange; dz++) {
      drawChunk(chunkX + dx, chunkZ + dz);
    }
  }
}
void updateCamera() {
  yaw += (mouseX - pmouseX) * sensitivity;
  pitch -= (mouseY - pmouseY) * sensitivity;
  pitch = constrain(pitch, -PI / 2 + 0.1, PI / 2 - 0.1);
  float lookX = cos(yaw) * cos(pitch);
  float lookY = sin(pitch);
  float lookZ = sin(yaw) * cos(pitch);
  if (moveForward) { camX += lookX * camSpeed; camZ += lookZ * camSpeed; }
  if (moveBackward) { camX -= lookX * camSpeed; camZ -= lookZ * camSpeed; }
  float strafeX = cos(yaw + PI / 2);
  float strafeZ = sin(yaw + PI / 2);
  if (moveLeft) { camX -= strafeX * camSpeed; camZ -= strafeZ * camSpeed; }
  if (moveRight) { camX += strafeX * camSpeed; camZ += strafeZ * camSpeed; }
  if (moveUp) camY += camSpeed;
  if (moveDown) camY -= camSpeed;
  float groundY = getTerrainHeight(camX, camZ);
  if (camY < groundY + cameraGroundOffset) camY = groundY + cameraGroundOffset;
}
void applyCamera() {
  float lookX = cos(yaw) * cos(pitch);
  float lookY = sin(pitch);
  float lookZ = sin(yaw) * cos(pitch);
  camera(camX, camY, camZ, camX + lookX, camY + lookY, camZ + lookZ, 0, -1, 0);
  directionalLight(255, 255, 255, 0, -1, 0);
}
float getTerrainHeight(float x, float z) {
  int chunkX = floor(x / chunkSize);
  int chunkZ = floor(z / chunkSize);
  int chunkType = getChunkType(chunkX, chunkZ);
  
  if (chunkType == 2) { // Montaña
    return noise(x * noiseScale + seed * 100, z * noiseScale + seed * 100) * mountainHeightScale;
  } else {
    return noise(x * noiseScale + seed * 100, z * noiseScale + seed * 100) * terrainHeightScale;
  }
}
int getChunkType(int cx, int cz) {
  String key = cx + "," + cz;
  if (chunkTypes.containsKey(key)) return chunkTypes.get(key);
  float r = random(1);
  int type = 0;
  if (r < 0.1) type = 2;       // Montaña
  else if (r < 0.4) type = 1;  // Ciudad
  else type = 0;               // Pradera
  chunkTypes.put(key, type);
  return type;
}
void drawChunk(int cx, int cz) {
  float baseX = cx * chunkSize;
  float baseZ = cz * chunkSize;
  String key = cx + "," + cz;
  int type = getChunkType(cx, cz);
  drawTerrain(baseX, baseZ); // AGREGADA: llamada para dibujar el terreno
  drawPradera(baseX, baseZ, key); // pradera base común a todo
  if (type == 1) drawCiudad(baseX, baseZ, key);
  // Removido drawMontaña porque ahora se hace con el terreno
}
void drawTerrain(float baseX, float baseZ) {
  int chunkX = floor(baseX / chunkSize);
  int chunkZ = floor(baseZ / chunkSize);
  int chunkType = getChunkType(chunkX, chunkZ);
  
  if (chunkType == 2) { // Montaña
    fill(139, 137, 137); // color gris montaña
  } else {
    fill(34, 139, 34); // color verde pradera
  }
  
  stroke(0, 80, 0, 50);
  for (float x = baseX; x < baseX + chunkSize; x += gridSize) {
    for (float z = baseZ; z < baseZ + chunkSize; z += gridSize) {
      float y1 = getTerrainHeight(x, z);
      float y2 = getTerrainHeight(x + gridSize, z);
      float y3 = getTerrainHeight(x + gridSize, z + gridSize);
      float y4 = getTerrainHeight(x, z + gridSize);
      beginShape(QUADS);
      vertex(x, y1, z);
      vertex(x + gridSize, y2, z);
      vertex(x + gridSize, y3, z + gridSize);
      vertex(x, y4, z + gridSize);
      endShape();
    }
  }
  noStroke();
}
void drawPradera(float baseX, float baseZ, String chunkKey) {
  int chunkX = floor(baseX / chunkSize);
  int chunkZ = floor(baseZ / chunkSize);
  int chunkType = getChunkType(chunkX, chunkZ);
  
  // Solo dibujar árboles si no es montaña
  if (chunkType != 2) {
    ArrayList<PVector> trees;
    if (treesPerChunk.containsKey(chunkKey)) {
      trees = treesPerChunk.get(chunkKey);
    } else {
      trees = new ArrayList<PVector>();
      for (int i = 0; i < 8; i++) {
        float x = baseX + random(0, chunkSize);
        float z = baseZ + random(0, chunkSize);
        float y = getTerrainHeight(x, z);
        trees.add(new PVector(x, y, z));
      }
      treesPerChunk.put(chunkKey, trees);
    }
    for (PVector tree : trees) {
      pushMatrix();
      translate(tree.x, tree.y + 20, tree.z);
      fill(139, 69, 19); box(10, 40, 10); // tronco
      translate(0, -30, 0); fill(0, 128, 0); sphere(20); // follaje
      popMatrix();
    }
  }
}
void drawCiudad(float baseX, float baseZ, String chunkKey) {
  ArrayList<PVector> buildings;
  if (buildingsPerChunk.containsKey(chunkKey)) {
    buildings = buildingsPerChunk.get(chunkKey);
  } else {
    buildings = new ArrayList<PVector>();
    int grid = 100;
    for (int i = 0; i < chunkSize; i += grid) {
      for (int j = 0; j < chunkSize; j += grid) {
        if (i % 200 == 0 || j % 200 == 0) continue; // calles cada 200 unidades
        float x = baseX + i + 10;
        float z = baseZ + j + 10;
        float y = getTerrainHeight(x, z);
        buildings.add(new PVector(x, y, z));
      }
    }
    buildingsPerChunk.put(chunkKey, buildings);
  }
  for (PVector b : buildings) {
    float h = 100 + (int)(noise(b.x * 0.01, b.z * 0.01) * 60); // altura fija
    pushMatrix();
    translate(b.x, b.y + h / 2, b.z);
    fill(100); box(60, h, 60);
    popMatrix();
  }
  
  // Calles horizontales y verticales
  stroke(100); fill(50);
  
  // Calles verticales (van de norte a sur)
  for (int i = 0; i <= chunkSize; i += 200) {
    for (float j = 0; j < chunkSize; j += 20) {
      float x = baseX + i;
      float z = baseZ + j;
      float y = getTerrainHeight(x, z);
      pushMatrix();
      translate(x, y + 0.5, z);
      box(40, 1, 20);
      popMatrix();
    }
  }
  
  // Calles horizontales (van de este a oeste)
  for (int j = 0; j <= chunkSize; j += 200) {
    for (float i = 0; i < chunkSize; i += 20) {
      float x = baseX + i;
      float z = baseZ + j;
      float y = getTerrainHeight(x, z);
      pushMatrix();
      translate(x, y + 0.5, z);
      box(20, 1, 40);
      popMatrix();
    }
  }
  
  noStroke(); // AGREGADO: resetear stroke después de dibujar las calles
}
void drawMontaña(float baseX, float baseZ) {
  float cx = baseX + chunkSize / 2;
  float cz = baseZ + chunkSize / 2;
  float cy = getTerrainHeight(cx, cz);
  float h = 300;
  float r = 100;
  pushMatrix();
  translate(cx, cy, cz);
  fill(139, 137, 137);
  beginShape(TRIANGLE_FAN);
  vertex(0, h, 0);
  for (int i = 0; i <= 24; i++) {
    float a = TWO_PI * i / 24;
    float x = cos(a) * r;
    float z = sin(a) * r;
    vertex(x, 0, z);
  }
  endShape();
  popMatrix();
}
void keyPressed() {
  if (key == 'w' || key == 'W') moveForward = true;
  if (key == 's' || key == 'S') moveBackward = true;
  if (key == 'd' || key == 'D') moveLeft = true;
  if (key == 'a' || key == 'A') moveRight = true;
  if (key == 'q' || key == 'Q') moveUp = true;
  if (key == 'e' || key == 'E') moveDown = true;
}
void keyReleased() {
  if (key == 'w' || key == 'W') moveForward = false;
  if (key == 's' || key == 'S') moveBackward = false;
  if (key == 'd' || key == 'D') moveLeft = false;
  if (key == 'a' || key == 'A') moveRight = false;
  if (key == 'q' || key == 'Q') moveUp = false;
  if (key == 'e' || key == 'E') moveDown = false;
}
