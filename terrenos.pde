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
HashMap<String, Integer> chunkTypes = new HashMap<String, Integer>(); // 0=pradera,1=ciudad,2=montaña

float gridSize = 40;
float noiseScale = 0.01;
float terrainHeightScale = 22;
float mountainHeightScale = 160;

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

  // Aplicar
  camX += mv.x;
  camY += mv.y;
  camZ += mv.z;

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
  if (chunkTypes.containsKey(k)) return chunkTypes.get(k);

  // Base determinista (ruido + hash)
  float r = 0.65*noise((cx+seed)*0.17, (cz-seed)*0.17) + 0.35*hash2i(cx,cz);

  int type;
  if (r > 0.78)      type = 2; // montaña
  else if (r > 0.10) type = 1; // ciudad
  else               type = 0; // pradera

  // Si es montaña, evitar ciudades pegadas (4-neighborhood)
  if (type == 2){
    // etiquetar vecinos como pradera (salvo otras montañas)
    int[][] nbs = {{1,0},{-1,0},{0,1},{0,-1}};
    for (int i=0;i<nbs.length;i++){
      int nx=cx+nbs[i][0], nz=cz+nbs[i][1];
      String nk = keyOf(nx,nz);
      if (!chunkTypes.containsKey(nk)){
        float rr = 0.65*noise((nx+seed)*0.17, (nz-seed)*0.17) + 0.35*hash2i(nx,nz);
        int t2 = (rr > 0.78) ? 2 : 0; // vecino solo montaña o pradera, no ciudad
        chunkTypes.put(nk, t2);
      } else {
        if (chunkTypes.get(nk) == 1) chunkTypes.put(nk, 0);
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

  if (ct == 1){
    return cityBaseY; // piso plano para ciudad
  } else if (ct == 2){
    // Centro del chunk para una “cúpula” suave
    float centerX = cx*chunkSize + chunkSize*0.5;
    float centerZ = cz*chunkSize + chunkSize*0.5;
    float d = dist(x, z, centerX, centerZ);
    float r0 = chunkSize*0.42;     // radio completo
    float r1 = chunkSize*0.52;     // cola de desvanecimiento
    float mask = 1.0 - smoothstep(r0, r1, d);  // 1 en el centro, 0 en borde/afuera

    float base = noise(x*noiseScale + seed*100, z*noiseScale + seed*100) * terrainHeightScale * 0.55;
    float peak = noise(x*noiseScale*0.6 + 999, z*noiseScale*0.6 + 999) * mountainHeightScale;
    float h = base + peak * mask + 8*mask; // leve pedestal

    // Transición adicional si vecino es pradera/ciudad (borde más gentil)
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
    if (abs(localX - rx) <= (roadWidth/2 + sidewalkWidth)) return true;
  }
  // horizontales
  for (int rz = 0; rz <= chunkSize; rz += 200){
    if (abs(localZ - rz) <= (roadWidth/2 + sidewalkWidth)) return true;
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

// Pradera: sólo árboles (ya no se cuelan en ciudad/calles)
  if (type != 2) drawPradera(baseX, baseZ, key, type);

  if (type == 1) drawCiudad(baseX, baseZ, key);
}

void generateCloudsForChunk(int cx, int cz){
  String key = keyOf(cx, cz);
  if (cloudsPerChunk.containsKey(key)) return; // ya generado

  int cloudsCount = 4 + (int)random(0,2); // 4-5 nubes
  ArrayList<PVector> localClouds = new ArrayList<PVector>();

  for(int i=0; i<cloudsCount; i++){
    float x = cx*chunkSize + random(0, chunkSize);
    float z = cz*chunkSize + random(0, chunkSize);
    float y = cloudY + random(-10,10);
    PVector c = new PVector(x,y,z);
    clouds.add(c); // lista global para dibujar
    localClouds.add(c); // lista local del chunk
  }

  cloudsPerChunk.put(key, localClouds);
}

void drawTerrain(float baseX, float baseZ, int type){
  // Color según bioma (montaña grisácea)
  if (type == 2) fill(139,137,137);
  else if (type == 1) fill(80, 120, 80); // debajo de ciudad, oscuro discreto
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
    fill(255, 255, 255, 180);
    
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
  pushMatrix();
  translate(width*0.22, height-80);
  // Marco
  stroke(255);
  noFill();
  ellipse(0, 0, 120, 120);
  // Disco cielo/tierra desplazado por pitch (sin roll en esta simulación)
  float pitchOffset = map(pitch, -PI/2, PI/2, -50, 50);
  stroke(200);
  line(-60, pitchOffset, 60, pitchOffset);     // línea de horizonte
  stroke(0,255,0);
  line(0, -50, 0, 50);                         // referencia vertical
  fill(255);
  noStroke();
  textAlign(CENTER, CENTER);
  textSize(12);
  text("HORIZONTE", 0, 70);
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
