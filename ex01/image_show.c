#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define sign(x) ((x > 0) - (x < 0))
#define MAX(x, y) x > y ? x : y
#define MIN(x, y) x > y ? y : x

typedef struct ImagePGM {
  uint16_t *buffer;
  uint16_t max_gray;
  uint16_t width;
  uint16_t height;
} ImagePGM;

typedef struct RGB {
  uint8_t r;
  uint8_t g;
  uint8_t b;
} RGB;

typedef struct ImagePPM {
  RGB *buffer;
  uint16_t width;
  uint16_t height;
} ImagePPM;

typedef struct Point2D {
  uint16_t x;
  uint16_t y;
} Point2D;

typedef struct Axis {
  double padding;
  uint16_t width;
} Axis;

// void lineplot(Axis ax, uint16_t *x, uint16_t *y, size_t N) {}

int ImagePPM_save(ImagePPM const *img, char const *filepath) {
  FILE *file = fopen(filepath, "wb");
  if (!file) {
    fprintf(stderr, "Não conseguiu salvar o arquivo %s\n", filepath);
    return 1;
  }
  fprintf(file, "P6\n%hu %hu\n%hu\n", img->width, img->height, 255);
  size_t total_pixels = (size_t)img->height * (size_t)img->width;
  if (fwrite(img->buffer, sizeof(RGB), total_pixels, file) != total_pixels) {
    fprintf(stderr, "Erro na escrita do buffer da imagem %s\n", filepath);
    fclose(file);
    return 1;
  }
  fclose(file);
  return 0;
}

ImagePPM ImagePPM_create_solid_canvas(RGB color, uint16_t width,
                                      uint16_t height) {
  ImagePPM img = {0};
  img.width = width;
  img.height = height;
  img.buffer = malloc(sizeof(RGB) * img.width * img.height);
  for (size_t i = 0; i < (size_t)img.width * img.height; i++) {
    img.buffer[i].r = color.r;
    img.buffer[i].b = color.g;
    img.buffer[i].g = color.g;
  }
  return img;
}

int __ImagePPM_draw_shallow_rectangle(ImagePPM *img, RGB color, Point2D p1,
                                    Point2D p2, uint16_t width) {
  uint16_t x_min = MIN(p1.x, p2.x);
  uint16_t x_max = MAX(p1.x, p2.x);
  uint16_t y_min = MIN(p1.y, p2.y);
  uint16_t y_max = MAX(p1.y, p2.y);
  if (x_max > img->width) {
    printf("x=%hu é maior que img.width=%hu", x_max, img->width);
    return 1;
  }
  if (y_max > img->height) {
    printf("y=%hu é maior que img.width=%hu", y_max, img->height);
    return 1;
  }

  for (uint16_t x = x_min; x <= x_max; x++) {
    for (uint16_t i = 0; i < width; i++) {
      img->buffer[img->width * (y_min + i) + x] = color;
      img->buffer[img->width * (y_max - i) + x] = color;
    }
  }
  for (uint16_t y = y_min; y <= y_max; y++) {
    for (uint16_t i = 0; i < width; i++) {
      img->buffer[img->width * y + (x_min + i)] = color;
      img->buffer[img->width * y + (x_max - i)] = color;
    }
  }
  return 0;
}

int ImagePPM_draw_ax(ImagePPM *img, Axis ax) {
  return __ImagePPM_draw_shallow_rectangle(
      img, (RGB){0, 0, 0},
      (Point2D){img->width * ax.padding, img->height * ax.padding},
      (Point2D){img->width * (1 - ax.padding), img->height * (1 - ax.padding)},
      ax.width);
}

void ImagePPM_close(ImagePPM *img) {
  free(img->buffer);
  img->height = 0;
  img->width = 0;
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

  uint16_t width = 800;
  uint16_t height = 600;
  ImagePPM img_test =
      ImagePPM_create_solid_canvas((RGB){.r=255, .g=255, .b=255}, width, height);
  ImagePPM_draw_ax(&img_test, (Axis){.width=10,.padding=0.125});
  ImagePPM_save(&img_test, "teste.ppm");

  // uint16_t line_number;
  // while (1) {
  //   printf("Escolha uma linha a ser analisada:\n");
  //   if (scanf("%hu", &line_number) != 1) {
  //     while (getchar() != '\n')
  //       ;
  //     continue;
  //   }
  //   if (line_number >= img.height) {
  //     printf("Linha %hu fora da imagem (máximo %hu)\n", line_number,
  //            img.height - 1);
  //     continue;
  //   }
  //   break;
  // }
  ImagePPM_close(&img_test);
  ImagePGM_close(&img);
}
