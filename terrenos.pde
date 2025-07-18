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
float terrainHeightScale = 20; // Terreno plano
float mountainHeightScale = 150; // Montaña más alta

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
    float distance = dist(x, z, chunkX * chunkSize + chunkSize / 2, chunkZ * chunkSize + chunkSize / 2);
    float maxDistance = chunkSize * 0.5;
    float slopeFactor = constrain(1 - distance / maxDistance, 0, 1); // Gradual slope
    return noise(x * noiseScale + seed * 100, z * noiseScale + seed * 100) * mountainHeightScale * slopeFactor * 1.5 + terrainHeightScale * 2;
  } else if (chunkType == 1) { // Ciudad: terreno plano
    return terrainHeightScale * 0.5; // Terreno más bajo para evitar solapamiento
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
  drawTerrain(baseX, baseZ);
  drawPradera(baseX, baseZ, key);
  if (type == 1) drawCiudad(baseX, baseZ, key);
}

void drawTerrain(float baseX, float baseZ) {
  int chunkX = floor(baseX / chunkSize);
  int chunkZ = floor(baseZ / chunkSize);
  int chunkType = getChunkType(chunkX, chunkZ);
  
  if (chunkType == 2) {
    fill(139, 137, 137); // Gris montaña
  } else {
    fill(34, 139, 34); // Verde pradera
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

// Función auxiliar para verificar si una posición está en una calle o edificio
boolean isValidTreePosition(float localX, float localZ) {
  // CALLES: Las calles están en i=0, 200, 400... y j=0, 200, 400...
  // Cada calle tiene 40 de asfalto + 10 de acera a cada lado = 60 total
  
  // Verificar calles verticales (en X)
  for (int roadX = 0; roadX <= 500; roadX += 200) {
    if (abs(localX - roadX) <= 30) { // 30 = mitad del ancho total (60/2)
      return false; // Está en una calle vertical
    }
  }
  
  // Verificar calles horizontales (en Z)
  for (int roadZ = 0; roadZ <= 500; roadZ += 200) {
    if (abs(localZ - roadZ) <= 30) { // 30 = mitad del ancho total (60/2)
      return false; // Está en una calle horizontal
    }
  }
  
  // EDIFICIOS: Verificar si está en el área de un edificio
  // Los edificios están en una grilla de 100x100, saltando donde hay calles
  int gridX = (int)(localX / 100);
  int gridZ = (int)(localZ / 100);
  
  // Los edificios están en las posiciones que no son múltiplos de 2 (para evitar calles)
  if (gridX % 2 == 1 && gridZ % 2 == 1) {
    // Calcular el centro del edificio en esta grilla
    float buildingCenterX = (gridX * 100) + 50;
    float buildingCenterZ = (gridZ * 100) + 50;
    
    // Verificar si está dentro del área del edificio (60x60 con margen)
    if (abs(localX - buildingCenterX) < 35 && abs(localZ - buildingCenterZ) < 35) {
      return false; // Está dentro de un edificio
    }
  }
  
  return true; // Posición válida para árbol
}

void drawPradera(float baseX, float baseZ, String chunkKey) {
  int chunkX = floor(baseX / chunkSize);
  int chunkZ = floor(baseZ / chunkSize);
  int chunkType = getChunkType(chunkX, chunkZ);
  
  if (chunkType != 2) {
    ArrayList<PVector> trees;
    if (treesPerChunk.containsKey(chunkKey)) {
      trees = treesPerChunk.get(chunkKey);
    } else {
      trees = new ArrayList<PVector>();
      int attempts = 0;
      int maxAttempts = 50; // Evitar bucle infinito
      
      while (trees.size() < 8 && attempts < maxAttempts) {
        float x = baseX + random(0, chunkSize);
        float z = baseZ + random(0, chunkSize);
        float y = getTerrainHeight(x, z);
        
        // Evitar árboles en las calles y edificios
        if (chunkType == 1) {
          float localX = x - baseX;
          float localZ = z - baseZ;
          
          // Usar la función auxiliar para verificar si es una posición válida
          if (!isValidTreePosition(localX, localZ)) {
            attempts++;
            continue; // Saltar esta posición
          }
        }
        
        trees.add(new PVector(x, y, z));
        attempts++;
      }
      treesPerChunk.put(chunkKey, trees);
    }
    
    for (PVector tree : trees) {
      pushMatrix();
      translate(tree.x, tree.y, tree.z);
      fill(139, 69, 19); // Tronco
      box(10, 40, 10); // Tronco desde y hasta y+40
      translate(0, 40, 0); // Mover al tope del tronco
      fill(0, 128, 0); // Follaje
      sphere(25); // Follaje encima del tronco
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
    for (int i = 100; i < chunkSize; i += 200) { // Empezar en 100, saltar de 200 en 200
      for (int j = 100; j < chunkSize; j += 200) {
        // Crear edificios en las posiciones impares de la grilla
        float x = baseX + i + 10;
        float z = baseZ + j + 10;
        float y = getTerrainHeight(x, z);
        buildings.add(new PVector(x, y, z));
      }
    }
    buildingsPerChunk.put(chunkKey, buildings);
  }
  for (PVector b : buildings) {
    float h = 100 + (int)(noise(b.x * 0.01, b.z * 0.01) * 60);
    pushMatrix();
    translate(b.x, b.y + h / 2, b.z);
    fill(100); box(60, h, 60);
    popMatrix();
  }
  
  // Calles con aceras y líneas discontinuas
  float roadWidth = 40;
  float sidewalkWidth = 10;
  float sidewalkHeight = 2;
  
  // Calles verticales (asfalto, aceras y líneas)
  fill(0); // Asfalto negro
  stroke(100);
  for (int i = 0; i <= chunkSize; i += 200) {
    for (float j = 0; j < chunkSize; j += 20) {
      float x = baseX + i;
      float z = baseZ + j;
      float y = getTerrainHeight(x, z) + 0.5; // Elevar asfalto
      // Asfalto
      fill(0);
      pushMatrix();
      translate(x, y, z);
      box(roadWidth, 1, 20);
      popMatrix();
      // Aceras
      fill(150); // Gris acera
      pushMatrix();
      translate(x - roadWidth / 2 - sidewalkWidth / 2, y + sidewalkHeight / 2, z);
      box(sidewalkWidth, sidewalkHeight, 20);
      popMatrix();
      pushMatrix();
      translate(x + roadWidth / 2 + sidewalkWidth / 2, y + sidewalkHeight / 2, z);
      box(sidewalkWidth, sidewalkHeight, 20);
      popMatrix();
      // Líneas discontinuas
      fill(255, 255, 0); // Amarillo para líneas
      if (j % 40 < 20) { // Espaciado para líneas discontinuas
        pushMatrix();
        translate(x, y + 1.0, z); // Elevar más las líneas
        box(4, 0.2, 10);
        popMatrix();
      }
      fill(0); // Restaurar color asfalto para el próximo ciclo
    }
  }
  
  // Calles horizontales (asfalto, aceras y líneas)
  fill(0); // Asfalto negro
  for (int j = 0; j <= chunkSize; j += 200) {
    for (float i = 0; i < chunkSize; i += 20) {
      float x = baseX + i;
      float z = baseZ + j;
      float y = getTerrainHeight(x, z) + 0.5; // Elevar asfalto
      // Asfalto
      fill(0);
      pushMatrix();
      translate(x, y, z);
      box(20, 1, roadWidth);
      popMatrix();
      // Aceras
      fill(150); // Gris acera
      pushMatrix();
      translate(x, y + sidewalkHeight / 2, z - roadWidth / 2 + sidewalkWidth / 2);
      box(20, sidewalkHeight, sidewalkWidth);
      popMatrix();
      pushMatrix();
      translate(x, y + sidewalkHeight / 2, z + roadWidth / 2 + sidewalkWidth / 2);
      box(20, sidewalkHeight, sidewalkWidth);
      popMatrix();
      // Líneas discontinuas
      fill(255, 255, 0); // Amarillo para líneas
      if (i % 40 < 20) { // Espaciado para líneas discontinuas
        pushMatrix();
        translate(x, y + 1.0, z); // Elevar más las líneas
        box(10, 0.2, 4);
        popMatrix();
      }
      fill(0); // Restaurar color asfalto para el próximo ciclo
    }
  }
  noStroke();
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
