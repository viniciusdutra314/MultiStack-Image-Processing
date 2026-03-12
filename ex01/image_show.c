#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define sign(x) (((x) > 0) - ((x) < 0))
#define MAX(x, y) (x) > (y) ? (x) : (y)
#define MIN(x, y) (x) > (y) ? (y) : (x)
#define PI 3.1415926

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
  bool grid;
} Axis;

const uint8_t font_data[] = {
#embed "IBM_VGA_8x8.bin"
};

void ImagePPM_draw_char(ImagePPM *img, Point2D pos, char c, RGB color,
                        uint16_t scale) {
  uint8_t char_idx = (uint8_t)c;
  const uint8_t *bitmap = &font_data[char_idx * 8];

  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      if (bitmap[i] & (1 << (7 - j))) {
        for (uint16_t sy = 0; sy < scale; sy++) {
          for (uint16_t sx = 0; sx < scale; sx++) {
            uint32_t nx = pos.x + (j * scale) + sx;
            uint32_t ny = pos.y + (i * scale) + sy;
            if (nx < img->width && ny < img->height) {
              img->buffer[ny * img->width + nx] = color;
            }
          }
        }
      }
    }
  }
}

RGB ImagePPM_get_pixel(ImagePPM const *img, Point2D pos) {
  assert(pos.x<img->width && pos.y<img->height);
  return img->buffer[img->width * pos.y + pos.x];
}

void ImagePPM_set_pixel(ImagePPM *img, Point2D pos, RGB color) {
    assert(pos.x<img->width && pos.y<img->height);
  img->buffer[img->width * pos.y + pos.x] = color;
}

void ImagePPM_set_transparent_pixel(ImagePPM *img, Point2D pos, RGB pixel,
                                    double alpha) {
  RGB past_pixel = ImagePPM_get_pixel(img, pos);
  ImagePPM_set_pixel(img, pos,
                     (RGB){.r = pixel.r * alpha + past_pixel.r * (1.0 - alpha),
                           .g = pixel.g * alpha + past_pixel.g * (1.0 - alpha),
                           .b = pixel.b * alpha + past_pixel.b * (1.0 - alpha)});
};

void ImagePPM_draw_string(ImagePPM *img, Point2D pos, const char *str,
                          RGB color, uint16_t scale) {
  uint16_t current_x = pos.x;
  while (*str != '\0') {
    ImagePPM_draw_char(img, (Point2D){current_x, pos.y}, *str, color, scale);
    current_x += 8 * scale;
    str++;
  }
}

void ImagePPM_draw_line(ImagePPM *img, Point2D p1, Point2D p2, RGB color,
                        double alpha, uint16_t thickness) {
  int32_t delta_x = (int32_t)p2.x - (int32_t)p1.x;
  int32_t delta_y = (int32_t)p2.y - (int32_t)p1.y;
  uint16_t delta_gamma = MAX(abs(delta_x), abs(delta_y));
  for (uint16_t gamma = 0; gamma <= delta_gamma; gamma++) {
    uint16_t x = roundf((float)p1.x + (gamma * (float)delta_x / delta_gamma));
    uint16_t y = roundf((float)p1.y + (gamma * (float)delta_y / delta_gamma));
    int16_t offset = thickness / 2;
    for (int16_t dy = -offset; dy <= offset; dy++) {
      for (int16_t dx = -offset; dx <= offset; dx++) {
        uint32_t nx = x + dx;
        uint32_t ny = y + dy;
        if (nx < img->width && ny < img->height) {
          ImagePPM_set_transparent_pixel(img, (Point2D){.x = nx, .y = ny},
                                         color, alpha);
        }
      }
    }
  }
}

void ImagePPM_draw_lineplot(ImagePPM *img, Axis ax, double *x, double *y,
                            size_t N, RGB color, uint16_t thickness,
                            double alpha, double padding) {
  double x_min, x_max, y_min, y_max;
  x_min = y_min = INFINITY;
  x_max = y_max = -INFINITY;

  for (size_t i = 0; i < N; i++) {
    if (x[i] < x_min)
      x_min = x[i];
    if (x[i] > x_max)
      x_max = x[i];
    if (y[i] < y_min)
      y_min = y[i];
    if (y[i] > y_max)
      y_max = y[i];
  }
  double plot_x_start = img->width * (ax.padding + padding);
  double plot_x_end = img->width * (1.0 - ax.padding - padding);
  double plot_y_bottom = img->height * (1.0 - ax.padding - padding);
  double plot_y_top = img->height * (ax.padding + padding);

  double x_range = x_max - x_min;
  double y_range = y_max - y_min;

  for (size_t i = 0; i < N - 1; i++) {
    Point2D p1 = {
        .x = (uint16_t)(plot_x_start +
                        (x[i] - x_min) / x_range * (plot_x_end - plot_x_start)),
        .y = (uint16_t)(plot_y_bottom -
                        (y[i] - y_min) / y_range * (plot_y_bottom - plot_y_top))};

    Point2D p2 = {
        .x = (uint16_t)(plot_x_start + (x[i + 1] - x_min) / x_range *
                                           (plot_x_end - plot_x_start)),
        .y = (uint16_t)(plot_y_bottom - (y[i + 1] - y_min) / y_range *
                                             (plot_y_bottom - plot_y_top))};

    ImagePPM_draw_line(img, p1, p2, color, alpha, thickness);
  }
}

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

int ImagePPM_create_solid_canvas(ImagePPM* img,RGB color, uint16_t width,
                                      uint16_t height) {
  img->width = width;
  img->height = height;
  img->buffer = malloc(sizeof(*img->buffer) * img->width * img->height);
  if (!img->buffer){
      perror("Alocação de imagem solid canvas falhou");
      return 1;
  }
  for (size_t i = 0; i < (size_t)img->width * img->height; i++) {
    img->buffer[i].r = color.r;
    img->buffer[i].b = color.b;
    img->buffer[i].g = color.g;
  }
  return 0;
}

int ImagePPM_draw_shallow_rectangle(ImagePPM *img, RGB color, Point2D p1,
                                    Point2D p2, uint16_t thickness) {
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
    for (uint16_t i = 0; i < thickness; i++) {
      ImagePPM_set_pixel(img, (Point2D){.x = x, .y = (y_min + i)}, color);
      ImagePPM_set_pixel(img, (Point2D){.x = x, .y = (y_max - i)}, color);
    }
  }
  for (uint16_t y = y_min; y <= y_max; y++) {
    for (uint16_t i = 0; i < thickness; i++) {
      ImagePPM_set_pixel(img, (Point2D){.x = (x_max - i), .y = y}, color);
      ImagePPM_set_pixel(img, (Point2D){.x = (x_min + i), .y = y}, color);
    }
  }
  return 0;
}

int ImagePPM_draw_ax(ImagePPM *img, Axis ax) {
  uint16_t x_min = img->width * ax.padding;
  uint16_t x_max = img->width * (1 - ax.padding);
  uint16_t y_min = img->height * ax.padding;
  uint16_t y_max = img->height * (1 - ax.padding);

  if (ax.grid) {
    RGB grid_color = {200, 200, 200};
    int num_divs = 10;
    for (int i = 1; i < num_divs; i++) {
      uint16_t gx = x_min + (i * (x_max - x_min)) / num_divs;
      uint16_t gy = y_min + (i * (y_max - y_min)) / num_divs;
      ImagePPM_draw_line(img, (Point2D){gx, y_min}, (Point2D){gx, y_max},
                         grid_color, 2,1);
      ImagePPM_draw_line(img, (Point2D){x_min, gy}, (Point2D){x_max, gy},
                         grid_color, 2,1);
    }
  }

  return ImagePPM_draw_shallow_rectangle(img, (RGB){0, 0, 0},
                                         (Point2D){x_min, y_min},
                                         (Point2D){x_max, y_max}, ax.width);
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

  uint16_t width = 1920;
  uint16_t height = 1080;
  ImagePPM figure;
ImagePPM_create_solid_canvas(&figure,
      (RGB){.r = 255, .g = 255, .b = 255}, width, height);
  Axis ax = {.width = 10, .padding = 0.125, .grid = true};
  ImagePPM_draw_ax(&figure, ax);
  uint16_t line_number;
  while (1) {
    printf("Escolha uma linha a ser analisada:\n");
    if (scanf("%hu", &line_number) != 1) {
      while (getchar() != '\n')
        ;
      continue;
    }
    if (line_number >= img.height) {
      printf("Linha %hu fora da imagem (máximo %hu)\n", line_number,
             img.height - 1);
      continue;
    }
    break;
  }


  size_t subsampling = 4;
  size_t N = img.width / subsampling;
  double* x=malloc(sizeof(*x)*N);
  double* y=malloc(sizeof(*x)*N);

  for (size_t i = 0; i < N; i++) {
    x[i] = (double)i;
    y[i] = (double)img.buffer[line_number*img.width + i * subsampling];
  }
  double alpha=0.1;
  double padding=0.05;
  ImagePPM_draw_lineplot(&figure, ax, x, y, N, (RGB){255, 0, 0}, 5,alpha,padding);
  free(x);
  free(y);
  char title[255];
  sprintf(title, "PERFIL DE INTENSIDADE (minimo=%hu,maximo=%hu)",
          min_gray, max_gray);
  ImagePPM_draw_string(
      &figure,
      (Point2D){(uint16_t)(width * 0.15), (uint16_t)(height * 0.085)}, title,
      (RGB){0, 0, 0}, 3);

  ImagePPM_save(&figure, "figure.ppm");
  ImagePPM_close(&figure);
  ImagePGM_close(&img);
}
