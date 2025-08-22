import java.util.ArrayList;
import java.util.HashMap;

// ===================== Cámara =====================
float camX = 0, camY = 300, camZ = 0;
float camSpeed = 6;
float yaw = 0, pitch = 0;
float sensitivity = 0.005;
float cameraGroundOffset = 5;

// Teclas
boolean moveForward = false, moveBackward = false;
boolean moveLeft = false, moveRight = false;
boolean moveUp = false, moveDown = false;

// ===================== Mundo =====================
int chunkSize = 500;
int worldSize = 2000;
int seed = 12345;

HashMap<String, ArrayList<PVector>> cloudsPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, Boolean> cloudsGeneratedForChunk = new HashMap<String, Boolean>();
HashMap<String, ArrayList<PVector>> treesPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, ArrayList<PVector>> buildingsPerChunk = new HashMap<String, ArrayList<PVector>>();
HashMap<String, Integer> chunkTypes = new HashMap<String, Integer>(); // 0=pradera,1=ciudad,2=montaña,3=aeropuerto  
HashMap<String, Boolean> airportPerChunk = new HashMap<String, Boolean>();

float gridSize = 40;
float noiseScale = 0.01;
float terrainHeightScale = 22;
float mountainHeightScale = 160;

// Puedes poner esta variable al inicio de tu sketch, fuera de cualquier función
final float MAX_WORLD_HEIGHT = 1000;

// Ciudad
float cityBaseY = 11;      // Terreno plano bajo la ciudad (constante)
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
// No modifica controles ni lógica de terreno. Solo dibuja por encima y usa datos de cámara existentes.
float hudSpeed = 0;  // velocidad instantánea (u/seg)
float prevX, prevY, prevZ;
int prevT = 0;

// ===================== Util =====================
String keyOf(int cx, int cz){ return cx + "," + cz; }

float hash2i(int x, int y){
  int h = x * 374761393 + y * 668265263; // 32-bit mix
  h = (h ^ (h >> 13)) * 1274126177;
  h ^= (h >> 16);
  // [0,1)
  return (h & 0x7fffffff) / (float)0x80000000;
}

float smoothstep(float a, float b, float x){
  x = constrain((x-a)/(b-a), 0, 1);
  return x*x*(3-2*x);
}

float length2(float x, float z){ return sqrt(x*x+z*z); }

// ===================== Setup/Draw =====================
void setup(){
  size(800, 600, P3D);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
  noiseSeed(seed);
}

void draw(){
  background(135,206,235);

  updateCamera();
  applyCamera();

  int chunkX = floor(camX / chunkSize);
  int chunkZ = floor(camZ / chunkSize);
  int viewRange = 2;

  // ================== Nubes: eliminar las de chunks fuera de vista ==================
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
        clouds.remove(c); // eliminar de la lista global
      }
      keysToRemove.add(k);
    }
  }
  for (String k : keysToRemove){
    cloudsPerChunk.remove(k);
  }

  // ================== Terreno + contenido ==================
  for (int dx = -viewRange; dx <= viewRange; dx++){
    for (int dz = -viewRange; dz <= viewRange; dz++){
      int ncx = chunkX + dx;
      int ncz = chunkZ + dz;

      generateCloudsForChunk(ncx, ncz); // genera nubes 1 vez por chunk
      drawChunk(ncx, ncz);
    }
  }

  // Nubes (al final, transparentes y billboard)
  drawClouds();

  // ====== ACTUALIZACIÓN DE INSTRUMENTOS + HUD (agregado) ======
  updateHUDData();
  drawHUD();
}


// ===================== Cámara =====================
void updateCamera(){
  yaw += (mouseX - pmouseX) * sensitivity;
  pitch -= (mouseY - pmouseY) * sensitivity;
  pitch = constrain(pitch, -PI/2 + 0.1, PI/2 - 0.1);

  // Direcciones
  float lx = cos(yaw) * cos(pitch);
  float ly = sin(pitch);
  float lz = sin(yaw) * cos(pitch);
  float rightX = cos(yaw + PI/2.0);
  float rightZ = sin(yaw + PI/2.0);

  // Movimiento combinado + normalizado (strafe + avance + vertical)
  PVector mv = new PVector(0,0,0);
  if (moveForward) { mv.x += lx; mv.y += ly*0.0; mv.z += lz; }
  if (moveBackward){ mv.x -= lx; mv.y -= ly*0.0; mv.z -= lz; }
  if (moveRight)   { mv.x += rightX; mv.z += rightZ; }
  if (moveLeft)    { mv.x -= rightX; mv.z -= rightZ; }
  if (mv.mag() > 0) mv.normalize().mult(camSpeed);

  // Vertical independiente
  if (moveUp)   mv.y += camSpeed;
  if (moveDown) mv.y -= camSpeed;

 // Aplicar movimiento
  camX += mv.x;
  camY += mv.y;
  camZ += mv.z;

  // Lógica para el límite de altura
  if (camY >= 1000) {
    // Si el jugador supera los 1000m, muestra un mensaje de advertencia.
    // Lo más fácil es ponerlo en drawHUD() para que aparezca siempre
    // que la altura sea > 1000.
    
    // Si el jugador supera los 1200m, no le permitas subir más.
    if (camY >= 1200) {
      camY = 1200; // Fija la altura en 1200m
      // También puedes detener el movimiento hacia arriba
      moveUp = false;
    }
  }

  // Colisión con terreno
  float groundY = getTerrainHeight(camX, camZ);
  if (camY < groundY + cameraGroundOffset) camY = groundY + cameraGroundOffset;

  // Colisión con edificios (AABB)
  resolveBuildingCollision();
}

void applyCamera(){
  float lookX = cos(yaw) * cos(pitch);
  float lookY = sin(pitch);
  float lookZ = sin(yaw) * cos(pitch);
  camera(camX, camY, camZ, camX + lookX, camY + lookY, camZ + lookZ, 0, -1, 0);
  directionalLight(255,255,255, 0, -1, 0);
}

// ===================== Biomas y alturas =====================
// Tipos de chunk deterministas + exclusión de ciudades alrededor de montañas
int getChunkType(int cx, int cz){
  String k = keyOf(cx,cz);
  // 3) Aeropuerto tiene prioridad y es determinista
  if (isAirportChunk(cx, cz)) {
    chunkTypes.put(k, 3); // 3=aeropuerto
    return 3;
  }
  // Si ya se resolvió antes (y NO era aeropuerto), devolvés
  if (chunkTypes.containsKey(k)) return chunkTypes.get(k);
  // Base determinista (ruido + hash) para 0/1/2
  float r = 0.65*noise((cx+seed)*0.17, (cz-seed)*0.17) + 0.35*hash2i(cx,cz);
  int type;
  if (r > 0.78)      type = 2; // montaña
  else if (r > 0.10) type = 1; // ciudad
  else               type = 0; // pradera
  // Si es montaña, evitar ciudades pegadas (4-neighborhood)
  if (type == 2){
    int[][] nbs = {{1,0},{-1,0},{0,1},{0,-1}};
    for (int i=0;i<nbs.length;i++){
      int nx=cx+nbs[i][0], nz=cz+nbs[i][1];
      String nk = keyOf(nx,nz);
      // No tocar si el vecino es aeropuerto
      if (isAirportChunk(nx, nz)) {
        chunkTypes.put(nk, 3);
        continue;
      }
      if (!chunkTypes.containsKey(nk)){
        float rr = 0.65*noise((nx+seed)*0.17, (nz-seed)*0.17) + 0.35*hash2i(nx,nz);
        int t2 = (rr > 0.78) ? 2 : 0; // vecino: montaña o pradera, no ciudad
        chunkTypes.put(nk, t2);
      } else {
        int cur = chunkTypes.get(nk);
        if (cur == 1) chunkTypes.put(nk, 0); // ciudad -> pradera
      }
    }
  }
  chunkTypes.put(k, type);
  return type;
}

// Altura con máscara suave para montaña; ciudad plana
float getTerrainHeight(float x, float z){
  int cx = floor(x / chunkSize);
  int cz = floor(z / chunkSize);
  int ct = getChunkType(cx, cz);

  if (ct == 3){
    return cityBaseY; // aeropuerto plano
  } else if (ct == 1){
    return cityBaseY; // ciudad plana
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


// ===================== Rutas/edificios: lógica única =====================
// Calles a cada 200, con 40 de asfalto + 10 de acera por lado (60 total)
boolean isRoadLocal(float localX, float localZ){
  // verticales
  for (int rx = 0; rx <= chunkSize; rx += 200){
    if (abs(localX - rx) < (roadWidth/2 + sidewalkWidth + 5)) return true;
  }
  // horizontales
  for (int rz = 0; rz <= chunkSize; rz += 200){
    if (abs(localZ - rz) < (roadWidth/2 + sidewalkWidth + 5)) return true;
  }
  return false;
}

boolean isInsideBuildingFootprint(float localX, float localZ){
  // edificios 60x60 centrados en celdas (100,100), (300,100), ...
  for (int i = 100; i < chunkSize; i += 200){
    for (int j = 100; j < chunkSize; j += 200){
      float cx = i + 10 + 30; // +10 del offset original, centro de 60x60
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

  // Contenido SEGÚN tipo
  if (type == 0) {
    // ✅ Pradera: árboles solamente (ya no se meten en ciudad ni aeropuerto)
    drawPradera(baseX, baseZ, key, type);
  } else if (type == 1) {
    drawCiudad(baseX, baseZ, key);
  } else if (type == 3) {
    drawAirport(baseX, baseZ);
  }
}

boolean isAirportChunk(int cx, int cz){
  // Aeropuerto en el spawn y luego cada 100 chunks SOLO por ejes (no diagonales)
  return ( (cx == 0 && abs(cz) % 100 == 0) || (cz == 0 && abs(cx) % 100 == 0) );
}

void drawAirport(float baseX, float baseZ){ 
  float y = getTerrainHeight(baseX+chunkSize/2, baseZ+chunkSize/2); 
  
  // pista larga 
  pushMatrix(); 
  translate(baseX + chunkSize/2, y+1, baseZ + chunkSize/2); 
  fill(50); 
  box(chunkSize*0.8, 2, 100);
  popMatrix(); 
  
  // torre de control 
  pushMatrix(); 
  translate(baseX + chunkSize/2 - 100, y+50, baseZ + chunkSize/2); 
  fill(120,120,160); 
  box(40,100,40); 
  popMatrix();
  
  // hangar 
  pushMatrix(); 
  translate(baseX + chunkSize/2 + 100, y+25, baseZ + chunkSize/2); 
  fill(150,80,80); 
  box(120,50,120); 
  popMatrix(); 
}

void generateCloudsForChunk(int cx, int cz){
  String key = keyOf(cx, cz);
  if (cloudsPerChunk.containsKey(key)) return;

  // Alturas para los dos "pisos" de nubes
  float cloudY_low = 500;
  float cloudY_high = 900;

  // Generar la primera tanda de nubes (piso inferior)
  int cloudsCount_low = 8 + (int)random(0,1); // 2-3 nubes
  ArrayList<PVector> localClouds = new ArrayList<PVector>();
  for(int i=0; i<cloudsCount_low; i++){
    float x = cx*chunkSize + random(0, chunkSize);
    float z = cz*chunkSize + random(0, chunkSize);
    float y = cloudY_low + random(-10,10);
    PVector c = new PVector(x,y,z);
    clouds.add(c);
    localClouds.add(c);
  }

  // Generar la segunda tanda de nubes (piso superior)
  int cloudsCount_high = 8 + (int)random(0,1); // 2-3 nubes
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
  if (type == 2) fill(139,137,137);      // montaña
  else if (type == 1) fill(80, 120, 80); // ciudad (debajo)
  else if (type == 3) fill(90, 110, 90); // aeropuerto (suelo base)
  else fill(34,139,34);                  // pradera

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
    // Generación de árboles
    while (trees.size() < 10 && attempts < maxAttempts){
      float x = baseX + random(0, chunkSize);
      float z = baseZ + random(0, chunkSize);
      float y = getTerrainHeight(x, z);
    
      // Prohibir árboles en calles o edificios para cualquier chunk que no sea montaña
      float lx = x - baseX;
      float lz = z - baseZ;
      if (isRoadLocal(lx, lz) || isInsideBuildingFootprint(lx, lz)){
        attempts++; continue;
      }
    
      // Chequeo extra: no sobrepasar altura de edificios vecinos
      int cx = floor(x / chunkSize);
      int cz = floor(z / chunkSize);
      String k = keyOf(cx, cz);
      if (aabbsPerChunk.containsKey(k)){
        boolean collision = false;
        for (AABB box : aabbsPerChunk.get(k)){
          if (y + 40 > box.minY && y < box.maxY){ // altura tronco + margen
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

  // Dibujo árboles
  for (PVector t : trees){
    pushMatrix();
    translate(t.x, t.y, t.z);
    // Tronco
    fill(139,69,19);
    box(10, 40, 10);
    // Copa
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

    // Colocar edificios en celdas, fuera de calles
    for (int i = 100; i < chunkSize; i += 200){
      for (int j = 100; j < chunkSize; j += 200){
        float lx = i + 10 + 30;  // centro local
        float lz = j + 10 + 30;
        float x = baseX + lx;
        float z = baseZ + lz;
        float y = cityBaseY;

        buildings.add(new PVector(x, y, z));

        float h = 110 + (int)(noise(x * 0.01, z * 0.01) * 70);
        // AABB para colisión
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

  // Asfalto continuo (vertical + horizontal), leve offset para evitar z-fighting
  float yRoad = cityBaseY + 1;

  // Verticales
  fill(40, 40, 40);
  for (int rx = 0; rx <= chunkSize; rx += 200){
    fill(40, 40, 40);
    pushMatrix();
    translate(baseX + rx, yRoad, baseZ + chunkSize/2);
    box(roadWidth, 1, chunkSize);
    popMatrix();

    // Aceras a ambos lados (continuas)
    fill(150);
    pushMatrix();
    translate(baseX + rx - roadWidth/2 - sidewalkWidth/2, yRoad + sidewalkHeight/2, baseZ + chunkSize/2);
    box(sidewalkWidth, sidewalkHeight, chunkSize);
    popMatrix();
    pushMatrix();
    translate(baseX + rx + roadWidth/2 + sidewalkWidth/2, yRoad + sidewalkHeight/2, baseZ + chunkSize/2);
    box(sidewalkWidth, sidewalkHeight, chunkSize);
    popMatrix();

    // Línea discontinua central
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

    // Aceras a ambos lados
    fill(150);
    pushMatrix();
    translate(baseX + chunkSize/2, yRoad + sidewalkHeight/2, baseZ + rz - roadWidth/2 - sidewalkWidth/2);
    box(chunkSize, sidewalkHeight, sidewalkWidth);
    popMatrix();
    pushMatrix();
    translate(baseX + chunkSize/2, yRoad + sidewalkHeight/2, baseZ + rz + roadWidth/2 + sidewalkWidth/2);
    box(chunkSize, sidewalkHeight, sidewalkWidth);
    popMatrix();

    // Línea discontinua central
    for (float x = 0; x < chunkSize; x += 40){
      fill(255, 255, 0);
      pushMatrix();
      translate(baseX + x + 10, yRoad + 0.7, baseZ + rz);
      box(20, 0.2, 4);
      popMatrix();
    }
  }

  // Edificios (transparencia si cámara cerca)
  for (int i=0; i<buildings.size(); i++){
    PVector b = buildings.get(i);
    float h = 110 + (int)(noise(b.x * 0.01, b.z * 0.01) * 70);
    float distToCam = dist(b.x, b.z, camX, camZ);
    boolean near = distToCam < 80;

    pushMatrix();
    translate(b.x, b.y + h/2.0, b.z);
    // Semitransparente cuando estás MUY cerca (para “ver a través”)
    if (near){
      fill(100, 180); // alpha
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
  // revisar el chunk actual y vecinos por seguridad
  for (int dx=-1; dx<=1; dx++){
    for (int dz=-1; dz<=1; dz++){
      String k = keyOf(cx+dx, cz+dz);
      if (!aabbsPerChunk.containsKey(k)) continue;
      ArrayList<AABB> list = aabbsPerChunk.get(k);
      for (AABB box : list){
        if (box.contains(camX, camY, camZ)){
          // Empuje suave hacia la cara más cercana en XZ (no tocamos Y para permitir subir por afuera)
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

// ===================== Nubes (sin colisión) =====================
void drawClouds(){
noStroke();  
fill(255, 255, 255, 220); // gris-azulado con algo de transparencia
  for (PVector c : clouds){
    float d = dist(camX, camZ, c.x, c.z);
    float s = map(d, 0, 1200, 120, 40); // más chica si lejos

    // Billboard: rotar para mirar a la cámara
    pushMatrix();
    translate(c.x, c.y, c.z);
    
    // Rotación billboard
    float ang = atan2(camX - c.x, camZ - c.z);
    rotateY(ang);
    
    // Apagás luces SOLO para la nube
    noLights();  
    noStroke();
    fill(255, 255, 255, 100);
    
    // Dibujo del quad
    beginShape(QUADS);
    vertex(-s,  25, 0);
    vertex( s,  25, 0);
    vertex( s, -25, 0);
    vertex(-s, -25, 0);
    endShape();
   
    // Volvés a prenderlas para lo demás
    lights();
    popMatrix();
  }
}

// ===================== Cabina 2D (HUD) =====================
// Calcula velocidad instantánea a partir del desplazamiento de la cámara
void updateHUDData(){
  int t = millis();
  if (prevT == 0){
    prevX = camX; prevY = camY; prevZ = camZ; prevT = t; hudSpeed = 0;
    return;
  }
  float dt = max(1, t - prevT) / 1000.0; // segundos, evita división por cero
  float dx = camX - prevX;
  float dy = camY - prevY;
  float dz = camZ - prevZ;
  float d = sqrt(dx*dx + dy*dy + dz*dz);
  hudSpeed = d / dt; // unidades por segundo
  prevX = camX; prevY = camY; prevZ = camZ; prevT = t;
}

void drawHUD(){
  // Dibujo en overlay 2D sin profundidad ni luces
  hint(DISABLE_DEPTH_TEST);
  noLights();
  camera();
  ortho();

  pushStyle();
  // Panel inferior
  noStroke();
  fill(0, 120);
  rect(0, height-160, width, 160);

  // ------- Horizonte artificial (simplificado: muestra cabeceo) -------
 // ------- Horizonte artificial estilo real -------  
pushMatrix();
translate(width*0.22, height-80);

// Marco
stroke(200);
strokeWeight(2);
noFill();
ellipse(0,0,120,120);

// Clip circular (para que el cielo/tierra no salga del marco)
PGraphics pg = createGraphics(120,120);
pg.beginDraw();
pg.translate(60,60); // centro local
pg.noStroke();

// Rotación e inclinación según cámara
pg.pushMatrix();
pg.translate(0, map(pitch, -PI/4, PI/4, -40, 40)); // desplazamiento vertical por pitch

// Cielo (azul)
pg.fill(70,130,180);
pg.rect(-120,-120,240,120);

// Tierra (marrón)
pg.fill(139,69,19);
pg.rect(-120,0,240,120);

pg.popMatrix();
pg.endDraw();
image(pg,-60,-60);  // dibujar dentro del círculo

// Marcas fijas del avión
stroke(255,120,0);
strokeWeight(3);
line(-30,0,30,0);   // barra horizontal
line(0,-10,0,10);   // barra vertical corta

fill(255);
noStroke();
textAlign(CENTER,CENTER);
textSize(12);
text("HORIZONTE", 0,70);
popMatrix();


  // ------- Altímetro (numérico) -------
  pushMatrix();
  translate(width*0.44, height-80);
  stroke(255);
  noFill();
  ellipse(0,0,100,100);
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(12);
  text("ALT", 0, -50);
  textSize(16);
  text(nf(camY, 0, 1) + " m", 0, 5);
  popMatrix();

  // ------- Velocímetro (numérico) -------
  pushMatrix();
  translate(width*0.60, height-80);
  stroke(255);
  noFill();
  ellipse(0,0,100,100);
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(12);
  text("VEL", 0, -50);
  textSize(16);
  text(nf(hudSpeed, 0, 1) + " u/s", 0, 5);
  popMatrix();

  // ------- Indicador de Rumbo (compás simple) -------
  pushMatrix();
  translate(width*0.80, height-80);
  stroke(255);
  noFill();
  ellipse(0,0,120,120);
  // aguja norte fija en instrumento; el valor numérico refleja rumbo
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
  // Aviso de altura
  if (camY >= 1000) {
    pushStyle();
    textAlign(CENTER, CENTER);
    textSize(24);
    fill(255, 0, 0); // Texto en rojo
    text("ADVERTENCIA: Límite de altura próximo (1200m)", width/2, 50);
    popStyle();
  }

  // Restaurar estado 3D para el siguiente frame
  hint(ENABLE_DEPTH_TEST);
  perspective(PI / 3.0, float(width) / height, 0.1, 10000);
}

// ===================== Teclado =====================
void keyPressed(){
  if (key == 'w' || key == 'W') moveForward = true;
  if (key == 's' || key == 'S') moveBackward = true;
  if (key == 'd' || key == 'D') moveLeft = true;   // corregido
  if (key == 'a' || key == 'A') moveRight = true;  // corregido
  if (key == 'q' || key == 'Q') moveUp = true;
  if (key == 'e' || key == 'E') moveDown = true;
}
void keyReleased(){
  if (key == 'w' || key == 'W') moveForward = false;
  if (key == 's' || key == 'S') moveBackward = false;
  if (key == 'd' || key == 'D') moveLeft = false;
  if (key == 'a' || key == 'A') moveRight = false;
  if (key == 'q' || key == 'Q') moveUp = false;
  if (key == 'e' || key == 'E') moveDown = false;
}
