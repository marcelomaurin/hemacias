# -*- coding: utf-8 -*-
"""
Spyder Editor

This is a temporary script file.
"""

import os
from PIL import Image




def converter_imagens_cinza(diretorio_entrada, diretorio_saida):
    # Verifica se o diretório de saída existe. Se não, cria-o.
    if not os.path.exists(diretorio_saida):
        os.makedirs(diretorio_saida)
    
    # Percorre os arquivos no diretório de entrada
    for filename in os.listdir(diretorio_entrada):
        print(f"filename:{filename}")
        # Verifica se o arquivo é uma imagem .jpg
        if filename.lower().endswith(".jpg"):  
            # Cria os caminhos completos de entrada e saída para o arquivo
            caminho_entrada = os.path.join(diretorio_entrada, filename)
            caminho_saida = os.path.join(diretorio_saida, filename)
            
            # Abre a imagem
            with Image.open(caminho_entrada) as img:
                # Converte a imagem para cinza
                img_cinza = img.convert("L")
                # Salva a imagem convertida no diretório de saída
                img_cinza.save(caminho_saida)
            print(f"Imagem {filename} convertida para cinza e salva em {caminho_saida}.")


# Converte imagens em positivas coloridas testes:
diretorio_entrada = "D:/projetos/maurinsoft/hemacias/fotos/positivas coloridas testes"
diretorio_saida = "D:/projetos/maurinsoft/hemacias/fotos/positivas cinza testes"
converter_imagens_cinza(diretorio_entrada, diretorio_saida)


# Converte imagens em positivas coloridas treino:
diretorio_entrada = "D:/projetos/maurinsoft/hemacias/fotos/positivas coloridas treino"
diretorio_saida = "D:/projetos/maurinsoft/hemacias/fotos/positivas cinza treino"
converter_imagens_cinza(diretorio_entrada, diretorio_saida)

print('Finalizou\n')