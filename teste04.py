import cv2
import numpy as np
import argparse

total = 0

# Função para listar todos os dispositivos de vídeo disponíveis
def list_video_devices():
    index = 0
    arr = []
    while True:
        cap = cv2.VideoCapture(index)
        if not cap.read()[0]:
            break
        else:
            arr.append(f"Device {index}: {cap.getBackendName()}")
        cap.release()
        index += 1
    return arr

def setup():
    parser = argparse.ArgumentParser(description="Script para listar dispositivos de vídeo")
    parser.add_argument('-lv', '--list-videos', action='store_true', help="Listar todos os dispositivos de vídeo disponíveis")
    parser.add_argument('-ind', '--index', type=int, help="Índice do dispositivo de vídeo a ser usado")
    parser.add_argument('-max', '--max-value', type=int, default=100, help="Valor máximo para a faixa de verde")

    args = parser.parse_args()

    if args.list_videos:
        devices = list_video_devices()
        if devices:
            print("Dispositivos de vídeo disponíveis:")
            for device in devices:
                print(device)
        else:
            print("Nenhum dispositivo de vídeo encontrado.")
        return None
    else:
        return args.index if args.index is not None else 0, args.max_value

def filtra_verde(frame, maxima):
    # Criar uma cópia da imagem original para aplicar as mudanças
    filtered_image = frame.copy()

    # Criar uma máscara onde o canal verde é maior que o valor do maxima
    mask = frame[:, :, 1] > maxima

    # Aplicar a máscara para definir esses pixels como [0, 0, 0]
    filtered_image[mask] = [0, 0, 0]

    return filtered_image

def loop(index, max_value):
    print(f"max_value:{max_value}")
    # Inicializar a captura de vídeo
    cap = cv2.VideoCapture(index)
    if not cap.isOpened():
        print(f"Erro ao abrir a câmera com índice {index}")
        return

    global total

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Filtrar o verde da imagem
        filtered_image = filtra_verde(frame, max_value)

        # Converter para escala de cinza para detecção de círculos
        gray = cv2.cvtColor(filtered_image, cv2.COLOR_BGR2GRAY)
        gray_blurred = cv2.GaussianBlur(gray, (15, 15), 0)

        # Detectar círculos usando HoughCircles
        circles = cv2.HoughCircles(
            gray_blurred,
            cv2.HOUGH_GRADIENT,
            dp=1,
            minDist=10,
            param1=20,
            param2=20,
            minRadius=15,
            maxRadius=35
        )

        total_circulos = 0
        # Se círculos forem detectados, desenhá-los na imagem
        if circles is not None:
            circles = np.uint16(np.around(circles))
            total_circulos = len(circles[0])

            for circle in circles[0, :]:
                center = (circle[0], circle[1])
                radius = circle[2]
                cv2.circle(gray_blurred, center, radius, (0, 255, 0), 2)
                cv2.circle(frame, center, radius, (0, 255, 0), 2)

        if total < total_circulos:
            total = total_circulos

        # Escrever a legenda
        texto = f"(C)lear"
        cv2.putText(frame, texto, (frame.shape[1]-80, 80), cv2.FONT_HERSHEY_SIMPLEX,
                    0.7, (0, 255, 0), 2)

        # Escrever o total de círculos na imagem original
        texto = f"Total de hemacias: {total}"
        cv2.putText(frame, texto, (10, frame.shape[0] - 10), cv2.FONT_HERSHEY_SIMPLEX,
                    0.7, (0, 255, 0), 2)

        # Mostrar a imagem com círculos detectados
        cv2.imshow('Original', frame)

        # Verificar pressionamento de teclas
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('c'):
            total = 0

    # Liberar a captura de vídeo e fechar janelas
    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    setup_result = setup()
    if setup_result is not None:
        index, max_value = setup_result
        loop(index, max_value)

