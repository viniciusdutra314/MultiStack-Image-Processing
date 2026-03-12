#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ImagePGM {
  uint16_t *buffer;
  uint16_t max_gray;
  uint16_t width;
  uint16_t height;
} ImagePGM;

typedef struct RGB{
    uint16_t r;
    uint16_t g;
    uint16_t b;
} RGB;

typedef struct ImagePPM{
    RGB* buffer;
    uint16_t maxval;
    uint16_t width;
    uint16_t height;
} ImagePPM;

int ImagePPM_save(ImagePPM const* img, char const *filepath){
    FILE* file = fopen(filepath, "wb");
    if (!file){
        fprintf(stderr, "Não conseguiu salvar o arquivo %s\n", filepath);
        return 1;
    }
    fprintf(file, "P6\n%hu %hu\n%hu\n", img->width, img->height, img->maxval);
    size_t total_pixels = (size_t)img->height * (size_t)img->width;
    if(fwrite(img->buffer, sizeof(RGB), total_pixels, file) != total_pixels){
        fprintf(stderr, "Erro na escrita do buffer da imagem %s\n", filepath);
        fclose(file);
        return 1;
    }
    fclose(file);
    return 0;
}


void ImagePGM_close(ImagePGM *img) {
  free(img->buffer);
  img->max_gray = 0;
  img->height = 0;
  img->width = 0;
}

void skip_pgm_comments(FILE *fp) {
  int ch;
  while ((ch = fgetc(fp)) != EOF) {
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      continue;
    }
    if (ch == '#') {
      while ((ch = fgetc(fp)) != EOF && ch != '\n')
        ;
    } else {
      ungetc(ch, fp);
      break;
    }
  }
}

int read_pgm_file(char const *filepath, ImagePGM *img) {
  FILE *pgm_file = NULL;
  img->buffer = NULL;
  pgm_file = fopen(filepath, "r");
  if (!pgm_file) {
    perror("Erro ao abrir o arquivo");
    goto clean;
  }
  char magic_number[3];
  if (fscanf(pgm_file, "%2s", magic_number) != 1) {
    fprintf(stderr, "Erro ao ler o número mágico\n");
    goto clean;
  }
  skip_pgm_comments(pgm_file);
  if (strcmp(magic_number, "P2") != 0) {
    fprintf(stderr, "Erro: O arquivo não é um PGM do tipo P2 (ASCII)\n");
    goto clean;
  }
  skip_pgm_comments(pgm_file);
  if (fscanf(pgm_file, "%hu %hu", &(img->width), &(img->height)) != 2) {
    fprintf(stderr, "Erro: Dimensões da imagem inválidas ou ausentes\n");
    goto clean;
  }
  skip_pgm_comments(pgm_file);
  if (fscanf(pgm_file, "%hu", &(img->max_gray)) != 1) {
    fprintf(stderr, "Erro: Valor máximo de cinza inválido ou ausente\n");
    goto clean;
  }

  img->buffer = malloc(sizeof(uint16_t) * (size_t)(img->height * img->width));
  if (!img->buffer) {
    perror("Erro de alocação de memória (imagem muito grande)");
    goto clean;
  }

  for (int i = 0; i < img->height; i++) {
    for (int j = 0; j < img->width; j++) {
      if (fscanf(pgm_file, "%hu", &(img->buffer[i * img->width + j])) != 1) {
        fprintf(stderr, "Erro ao ler pixel na posição %d, %d\n", i, j);
        goto clean;
      }
    }
  }

  fclose(pgm_file);
  return 0;

clean:
  if (pgm_file) {
    fclose(pgm_file);
  }
  if (img->buffer) {
    ImagePGM_close(img);
  }
  return 1;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    printf("Especifique uma imagem .pgm de entrada\n");
    return 1;
  }
  ImagePGM img = {0};
  if (read_pgm_file(argv[1], &img)) {
    fprintf(stderr, "Erro na leitura da imagem %s\n", argv[1]);
    return 1;
  }
  printf("---------------\n");
  printf("Imagem (%s) com %d colunas e %d linhas \n", argv[1], img.width,
         img.height);

  uint16_t max_gray = 0;
  uint16_t min_gray = UINT16_MAX;
  for (size_t i = 0; i < (size_t)img.width * img.height; i++) {
    if (img.buffer[i] > max_gray)
      max_gray = img.buffer[i];
    if (img.buffer[i] < min_gray)
      min_gray = img.buffer[i];
  }
  printf("Maior valor de cinza: %hu \n", max_gray);
  printf("Menor valor de cinza: %hu \n", min_gray);
  printf("Maior cinza definido no arquivo %hu \n", img.max_gray);
  printf("---------------\n");

  ImagePPM img_test={0};
  img_test.width=1000;
  img_test.height=1000;
  img_test.maxval=255;
  img_test.buffer=malloc(sizeof(RGB)*img_test.width*img_test.height);
  for (size_t i = 0; i < (size_t)img_test.width * img_test.height; i++) {
    img_test.buffer[i].r = rand() % (img_test.maxval + 1);
    img_test.buffer[i].g = rand() % (img_test.maxval + 1);
    img_test.buffer[i].b = rand() % (img_test.maxval + 1);
  }
  ImagePPM_save(&img_test,"teste.ppm");


  uint16_t line_number;
  while (1) {
    printf("Escolha uma linha a ser analisada:\n");
    if (scanf("%hu", &line_number) != 1) {
      while (getchar() != '\n');
      continue;
    }
    if (line_number >= img.height) {
      printf("Linha %hu fora da imagem (máximo %hu)\n", line_number, img.height - 1);
      continue;
    }
    break;
  }
  ImagePGM_close(&img);
}
