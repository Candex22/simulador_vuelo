import cv2
import mediapipe as mp
import socket
import json

# MediaPipe setup
mp_hands = mp.solutions.hands
hands = mp_hands.Hands(max_num_hands=2, min_detection_confidence=0.7)
mp_drawing = mp.solutions.drawing_utils

# TCP server
HOST = '127.0.0.1'
PORT = 5005
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind((HOST, PORT))
s.listen(1)
print("Waiting for Processing connection...")
conn, addr = s.accept()
print(f"Connected to {addr}")

cap = cv2.VideoCapture(0)

while True:
    ret, frame = cap.read()
    if not ret:
        continue

    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    result = hands.process(frame_rgb)

    hands_data = []
    if result.multi_hand_landmarks and result.multi_handedness:
        for hand_landmarks, handedness in zip(result.multi_hand_landmarks, result.multi_handedness):
            landmarks_list = []
            for lm in hand_landmarks.landmark:
                landmarks_list.append([lm.x, lm.y, lm.z])
            
            # Get hand label (Left or Right)
            hand_label = handedness.classification[0].label
            hands_data.append({
                "label": hand_label,
                "landmarks": landmarks_list
            })

    # Send data to Processing
    data = json.dumps(hands_data)
    try:
        conn.sendall((data + "\n").encode('utf-8'))
    except:
        print("Connection lost")
        break

cap.release()
conn.close()
s.close()
