#include <stddef.h>
#define _DEFAULT_SOURCE
#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <string.h>

#define sign(x) (((x) > 0) - ((x) < 0))
#define MAX(x, y) ((x) > (y) ? (x) : (y))
#define MIN(x, y) ((x) > (y) ? (y) : (x))
#define ABS(x) ((x) > 0 ? (x) : (-(x)))
#define PI 3.1415926

typedef enum ImageType { IMG_GRAY8, IMG_GRAY16, IMG_RGB8, IMG_RGB16 } ImageType;

typedef uint16_t Sample16;
typedef uint8_t Sample8;

typedef struct RGB16 {
  Sample16 r;
  Sample16 g;
  Sample16 b;
} RGB16;

typedef struct RGB8 {
  Sample8 r;
  Sample8 g;
  Sample8 b;
} RGB8;

typedef struct NetpbmImage {
  void *raw_image;
  size_t width;
  size_t height;
  ImageType type;
  Sample16 max_intensity;
} NetpbmImage;

typedef struct Point2D {
  size_t x;
  size_t y;
} Point2D;

typedef struct Axis {
  double padding;
  size_t width;
  bool grid;
} Axis;

const uint8_t font_data[] = {
#embed "IBM_VGA_8x8.bin"
};

Sample16 RGB16_to_intensity(RGB16 color) {
  return (Sample16)(0.299 * color.r + 0.587 * color.g + 0.114 * color.b);
};

RGB16 NetpbmImage_get_pixel(NetpbmImage const *img, Point2D pos) {
  assert(pos.x < img->width && pos.y < img->height);
  size_t idx = (size_t)img->width * pos.y + pos.x;
  switch (img->type) {
  case IMG_GRAY8: {
    uint8_t val = ((uint8_t *)img->raw_image)[idx];
    return (RGB16){val, val, val};
  }
  case IMG_GRAY16: {
    uint16_t val = ((uint16_t *)img->raw_image)[idx];
    return (RGB16){val, val, val};
  }
  case IMG_RGB8: {
    RGB8 *pixels = (RGB8 *)img->raw_image;
    return (RGB16){pixels[idx].r, pixels[idx].g, pixels[idx].b};
  }
  case IMG_RGB16:
  default:
    return ((RGB16 *)img->raw_image)[idx];
  }
}

void NetpbmImage_set_pixel(NetpbmImage *img, Point2D pos, RGB16 color) {
  assert(pos.x < img->width && pos.y < img->height);
  size_t idx = (size_t)img->width * pos.y + pos.x;
  switch (img->type) {
  case IMG_GRAY8: {
    ((uint8_t *)img->raw_image)[idx] =
        (uint8_t)(0.299 * color.r + 0.587 * color.g + 0.114 * color.b);
    break;
  }
  case IMG_GRAY16: {
    ((uint16_t *)img->raw_image)[idx] =
        (uint16_t)(0.299 * color.r + 0.587 * color.g + 0.114 * color.b);
    break;
  }
  case IMG_RGB8: {
    RGB8 *pixels = (RGB8 *)img->raw_image;
    pixels[idx].r = (uint8_t)color.r;
    pixels[idx].g = (uint8_t)color.g;
    pixels[idx].b = (uint8_t)color.b;
    break;
  }
  case IMG_RGB16:
  default: {
    ((RGB16 *)img->raw_image)[idx] = color;
    break;
  }
  }
}

void NetpbmImage_set_transparent_pixel(NetpbmImage *img, Point2D pos,
                                       RGB16 pixel, double alpha) {
  RGB16 past_pixel = NetpbmImage_get_pixel(img, pos);
  NetpbmImage_set_pixel(
      img, pos,
      (RGB16){.r = pixel.r * alpha + past_pixel.r * (1.0 - alpha),
              .g = pixel.g * alpha + past_pixel.g * (1.0 - alpha),
              .b = pixel.b * alpha + past_pixel.b * (1.0 - alpha)});
};

void NetpbmImage_draw_char(NetpbmImage *img, Point2D pos, char c, RGB16 color,
                           size_t scale) {
  uint8_t char_idx = (uint8_t)c;
  const uint8_t *bitmap = &font_data[char_idx * 8];

  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      if (bitmap[i] & (1 << (7 - j))) {
        for (uint16_t sy = 0; sy < scale; sy++) {
          for (uint16_t sx = 0; sx < scale; sx++) {
            NetpbmImage_set_pixel(img,
                                  (Point2D){.x = pos.x + (j * scale) + sx,
                                            .y = pos.y + (i * scale) + sy},
                                  color);
          }
        }
      }
    }
  }
}

void NetpbmImage_draw_string(NetpbmImage *img, Point2D pos, const char *str,
                             RGB16 color, size_t scale) {
  while (*str != '\0') {
    NetpbmImage_draw_char(img, (Point2D){pos.x, pos.y}, *str, color, scale);
    pos.x += 8 * scale;
    str++;
  }
}

void NetpbmImage_draw_line(NetpbmImage *img, Point2D p1, Point2D p2,
                           RGB16 color, double alpha, size_t thickness) {
  ptrdiff_t delta_x = (ptrdiff_t)p2.x - (ptrdiff_t)p1.x;
  ptrdiff_t delta_y = (ptrdiff_t)p2.y - (ptrdiff_t)p1.y;
  size_t delta_gamma = MAX(ABS(delta_x), ABS(delta_y));
  for (size_t gamma = 0; gamma <= delta_gamma; gamma++) {
    size_t x = round((double)p1.x + (gamma * (double)delta_x / delta_gamma));
    size_t y = round((double)p1.y + (gamma * (double)delta_y / delta_gamma));
    ptrdiff_t offset = thickness / 2;
    for (ptrdiff_t dy = -offset; dy <= offset; dy++) {
      for (ptrdiff_t dx = -offset; dx <= offset; dx++) {
        size_t nx = x + dx;
        size_t ny = y + dy;
        if (nx < img->width && ny < img->height) {
          NetpbmImage_set_transparent_pixel(img, (Point2D){.x = nx, .y = ny},
                                            color, alpha);
        }
      }
    }
  }
}

void NetpbmImage_draw_lineplot(NetpbmImage *img, Axis ax, double *x, double *y,
                               size_t N, RGB16 color, size_t thickness,
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
    Point2D p1 = {.x = (plot_x_start +
                        (x[i] - x_min) / x_range * (plot_x_end - plot_x_start)),
                  .y = (plot_y_bottom - (y[i] - y_min) / y_range *
                                            (plot_y_bottom - plot_y_top))};

    Point2D p2 = {.x = (plot_x_start + (x[i + 1] - x_min) / x_range *
                                           (plot_x_end - plot_x_start)),
                  .y = (plot_y_bottom - (y[i + 1] - y_min) / y_range *
                                            (plot_y_bottom - plot_y_top))};

    NetpbmImage_draw_line(img, p1, p2, color, alpha, thickness);
  }
}
int NetpbmImage_save(NetpbmImage const *img, char const *filepath) {
  FILE *file = fopen(filepath, "wb");
  if (!file) {
    fprintf(stderr, "Não conseguiu salvar o arquivo %s\n", filepath);
    return 1;
  }
  const char *magic_number;
  size_t pixel_size;
  switch (img->type) {
  case IMG_GRAY8:
    magic_number = "P5";
    pixel_size = sizeof(uint8_t);
    break;
  case IMG_GRAY16:
    magic_number = "P5";
    pixel_size = sizeof(uint16_t);
    break;
  case IMG_RGB8:
    magic_number = "P6";
    pixel_size = sizeof(RGB8);
    break;
  case IMG_RGB16:
  default:
    magic_number = "P6";
    pixel_size = sizeof(RGB16);
    break;
  }
  uint16_t max_intensity = 0;
  for (size_t i = 0; i < img->width ; i++) {
      for (size_t j=0;j<img->height;j++){
          Sample16 intensity =RGB16_to_intensity(NetpbmImage_get_pixel(img, (Point2D){i,j}));
          if (intensity> max_intensity) max_intensity = intensity;
      }
  }

  fprintf(file, "%s\n%zu %zu\n%hu\n", magic_number, img->width, img->height,
      max_intensity);
  size_t total_pixels = img->height * img->width;
  if (fwrite(img->raw_image, pixel_size, total_pixels, file) != total_pixels) {
    fprintf(stderr, "Erro na escrita do buffer da imagem %s\n", filepath);
    fclose(file);
    return 1;
  }

  fclose(file);
  return 0;
}

int NetpbmImage_create(NetpbmImage *img, size_t width, size_t height) {
  img->width = width;
  img->height = height;
  img->raw_image = nullptr;
  img->max_intensity=0;
  size_t total_pixels = width * height;
  switch (img->type) {
  case IMG_GRAY8:
    img->raw_image = malloc(sizeof(uint8_t) * total_pixels);
    break;
  case IMG_GRAY16:
    img->raw_image = malloc(sizeof(uint16_t) * total_pixels);
    break;
  case IMG_RGB8:
    img->raw_image = malloc(sizeof(RGB8) * total_pixels);
    break;
  case IMG_RGB16:
  default:
    img->raw_image = malloc(sizeof(RGB16) * total_pixels);
    break;
  }

  if (!img->raw_image) {
    perror("Alocação de imagem solid canvas falhou");
    return 1;
  }
  return 0;
}

int NetpbmImage_create_solid_canvas(NetpbmImage *img, RGB16 color, size_t width,
                                    size_t height) {
  if (NetpbmImage_create(img, width, height)) {
    return 1;
  }
  for (size_t y = 0; y < height; y++) {
    for (size_t x = 0; x < width; x++) {
      NetpbmImage_set_pixel(img, (Point2D){x, y}, color);
    }
  }
  return 0;
}

int NetpbmImage_draw_shallow_rectangle(NetpbmImage *img, RGB16 color,
                                       Point2D p1, Point2D p2,
                                       size_t thickness) {
  size_t x_min = MIN(p1.x, p2.x);
  size_t x_max = MAX(p1.x, p2.x);
  size_t y_min = MIN(p1.y, p2.y);
  size_t y_max = MAX(p1.y, p2.y);
  if (x_max > img->width) {
    printf("x=%zu é maior que img.width=%zu", x_max, img->width);
    return 1;
  }
  if (y_max > img->height) {
    printf("y=%zu é maior que img.width=%zu", y_max, img->height);
    return 1;
  }

  for (size_t x = x_min; x <= x_max; x++) {
    for (size_t i = 0; i < thickness; i++) {
      NetpbmImage_set_pixel(img, (Point2D){.x = x, .y = (y_min + i)}, color);
      NetpbmImage_set_pixel(img, (Point2D){.x = x, .y = (y_max - i)}, color);
    }
  }
  for (size_t y = y_min; y <= y_max; y++) {
    for (size_t i = 0; i < thickness; i++) {
      NetpbmImage_set_pixel(img, (Point2D){.x = (x_max - i), .y = y}, color);
      NetpbmImage_set_pixel(img, (Point2D){.x = (x_min + i), .y = y}, color);
    }
  }
  return 0;
}

int NetpbmImage_draw_ax(NetpbmImage *img, Axis ax) {
  size_t x_min = img->width * ax.padding;
  size_t x_max = img->width * (1 - ax.padding);
  size_t y_min = img->height * ax.padding;
  size_t y_max = img->height * (1 - ax.padding);

  if (ax.grid) {
    RGB16 grid_color = {200, 200, 200};
    size_t num_divs = 10;
    for (size_t i = 1; i < num_divs; i++) {
      size_t gx = x_min + (i * (x_max - x_min)) / num_divs;
      size_t gy = y_min + (i * (y_max - y_min)) / num_divs;
      NetpbmImage_draw_line(img, (Point2D){gx, y_min}, (Point2D){gx, y_max},
                            grid_color, 2, 1);
      NetpbmImage_draw_line(img, (Point2D){x_min, gy}, (Point2D){x_max, gy},
                            grid_color, 2, 1);
    }
  }

  return NetpbmImage_draw_shallow_rectangle(img, (RGB16){0, 0, 0},
                                            (Point2D){x_min, y_min},
                                            (Point2D){x_max, y_max}, ax.width);
}

void NetpbmImage_close(NetpbmImage *img) {
  free(img->raw_image);
  img->height = 0;
  img->width = 0;
  img->max_intensity = 0;
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
int NetpbmImage_read_file(char const *filepath, NetpbmImage *img) {
  FILE *pgm_file = NULL;
  img->raw_image = NULL;
  pgm_file = fopen(filepath, "rb");
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
  if (fscanf(pgm_file, "%zu %zu", &(img->width), &(img->height)) != 2) {
    fprintf(stderr, "Erro: Dimensões da imagem inválidas ou ausentes\n");
    goto clean;
  }

  skip_pgm_comments(pgm_file);
  if (fscanf(pgm_file, "%hu", &(img->max_intensity)) != 1) {
    fprintf(stderr, "Erro: Valor máximo de intensidade inválido ou ausente\n");
    goto clean;
  }
  if (strcmp(magic_number, "P2") == 0 || strcmp(magic_number, "P5") == 0) {
    img->type = (img->max_intensity <= 255) ? IMG_GRAY8 : IMG_GRAY16;
  } else if (strcmp(magic_number, "P3") == 0 ||
             strcmp(magic_number, "P6") == 0) {
    img->type = (img->max_intensity <= 255) ? IMG_RGB8 : IMG_RGB16;
  } else {
    fprintf(stderr, "Erro: Formato %s não suportado\n", magic_number);
    goto clean;
  }

  Sample16 saved_max_intensity = img->max_intensity;
  if (NetpbmImage_create(img, img->width, img->height) != 0) {
    goto clean;
  }
  img->max_intensity = saved_max_intensity;

  fgetc(pgm_file);
  if (strcmp(magic_number, "P2") == 0) {
    for (size_t i = 0; i < img->height; i++) {
      for (size_t j = 0; j < img->width; j++) {
        unsigned int val;
        if (fscanf(pgm_file, "%u", &val) != 1) {
          fprintf(stderr, "Erro ao ler pixel na posição %zu, %zu\n", i, j);
          goto clean;
        }
        NetpbmImage_set_pixel(
            img, (Point2D){j, i},
            (RGB16){(Sample16)val, (Sample16)val, (Sample16)val});
      }
    }
  } else if (strcmp(magic_number, "P3") == 0) {
    for (size_t i = 0; i < img->height; i++) {
      for (size_t j = 0; j < img->width; j++) {
        unsigned int r, g, b;
        if (fscanf(pgm_file, "%u %u %u", &r, &g, &b) != 3) {
          fprintf(stderr, "Erro ao ler pixel na posição %zu, %zu\n", i, j);
          goto clean;
        }
        NetpbmImage_set_pixel(img, (Point2D){j, i},
                              (RGB16){(Sample16)r, (Sample16)g, (Sample16)b});
      }
    }
  } else if (strcmp(magic_number, "P5") == 0) {
    size_t pixel_size = (img->type == IMG_GRAY8) ? 1 : 2;
    if (fread(img->raw_image, pixel_size, img->width * img->height, pgm_file) !=
        img->width * img->height) {
      fprintf(stderr, "Erro ao ler dados binários P5\n");
      goto clean;
    }
  } else if (strcmp(magic_number, "P6") == 0) {
    size_t pixel_size = (img->type == IMG_RGB8) ? sizeof(RGB8) : sizeof(RGB16);
    if (fread(img->raw_image, pixel_size, img->width * img->height, pgm_file) !=
        img->width * img->height) {
      fprintf(stderr, "Erro ao ler dados binários P6\n");
      goto clean;
    }
  }

  fclose(pgm_file);
  return 0;

clean:
  if (pgm_file) {
    fclose(pgm_file);
  }
  if (img->raw_image) {
    NetpbmImage_close(img);
  }
  return 1;
}

void NetpbmImage_show(NetpbmImage const *img) {
#ifdef __linux__
  char temp_filename[] = "/tmp/imageXXXXXX.ppm";
  int fd = mkstemps(temp_filename, 4);
  if (fd == -1) {
    perror("Erro ao criar arquivo temporário");
    return;
  }
  close(fd);
  if (NetpbmImage_save(img, temp_filename) == 0) {
    char command[256];
    snprintf(command, sizeof(command), "xdg-open %s", temp_filename);
    if (system(command) == -1) {
      perror("Erro ao executar visualizador de imagem");
    }
  }
#else
  fprintf(stderr,
          "Erro: Visualização de imagem só é suportada em sistemas Linux.\n");
#endif
}

void show_image(char const *filepath) {
#ifdef __linux__
  char command[256];
  sprintf(command, "xdg-open %s", filepath);
  if (system(command) == -1) {
    perror("Error ao visualizar a imagem");
  }
#else
  fprintf(stderr,
          "Erro: Visualização de imagem só é suportada em sistemas Linux.\n");
#endif
}

int main(int argc, char **argv) {
  if (argc != 3) {
    printf("Especifique uma imagem .pgm/.ppm de entrada e uma imagem saida "
           "para o gráfico\n");
    return 1;
  }
  char const *filepath_input_image = argv[1];
  char const *filepath_output_graph = argv[2];
  NetpbmImage img = {0};
  if (NetpbmImage_read_file(filepath_input_image, &img)) {
    fprintf(stderr, "Erro na leitura da imagem %s\n", filepath_input_image);
    return 1;
  }
  printf("---------------\n");
  printf("Imagem (%s) com %zu colunas e %zu linhas \n", filepath_input_image,
         img.width, img.height);

  Sample16 max_intensity = 0;
  Sample16 min_intensity = UINT16_MAX;
  for (size_t x = 0; x < img.width; x++) {
    for (size_t y = 0; y < img.height; y++) {
      Point2D point = {.x = x, .y = y};
      Sample16 intensity =
          RGB16_to_intensity(NetpbmImage_get_pixel(&img, point));
      if (intensity > max_intensity) {
        max_intensity = intensity;
      };
      if (intensity < min_intensity) {
        min_intensity = intensity;
      }
    }
  };

  printf("Maior valor de intensidade: %hu \n", max_intensity);
  printf("Menor valor de intensidade: %hu \n", min_intensity);
  printf("Maior intensidade definido no arquivo %hu \n", img.max_intensity);
  int possivel_resolucao_bits;
  if (img.max_intensity <= (1 << 8)) {
    possivel_resolucao_bits = 8;
  } else if (img.max_intensity <= (1 << 10)) {
    possivel_resolucao_bits = 10;
  } else if (img.max_intensity <= (1 << 12)) {
    possivel_resolucao_bits = 12;
  } else {
    possivel_resolucao_bits = 16;
  }
  printf("Resolução provável de %d bits \n", possivel_resolucao_bits);
  printf("---------------\n");

  uint16_t width = 1920;
  uint16_t height = 1080;
  NetpbmImage figure={.type=IMG_RGB8};
  NetpbmImage_create_solid_canvas(
      &figure, (RGB16){.r = 255, .g = 255, .b = 255}, width, height);
  Axis ax = {.width = 10, .padding = 0.125, .grid = true};
  NetpbmImage_draw_ax(&figure, ax);
  show_image(filepath_input_image);
  size_t line_number;
  while (1) {
    printf("Escolha uma linha a ser analisada:\n");
    if (scanf("%zu", &line_number) != 1) {
      while (getchar() != '\n')
        ;
      continue;
    }
    if (line_number >= img.height) {
      printf("Linha %zu fora da imagem (máximo %zu)\n", line_number,
             img.height - 1);
      continue;
    }
    break;
  }
  size_t N = img.width;
  double *x = malloc(sizeof(*x) * N);
  double *y = malloc(sizeof(*x) * N);
  Sample16 y_max = 0;
  Sample16 y_min = UINT16_MAX;
  for (size_t i = 0; i < N; i++) {
    x[i] = (double)i;
    Sample16 intensity = RGB16_to_intensity(
        NetpbmImage_get_pixel(&img, (Point2D){i, line_number}));
    y[i] = (double)intensity;
    if (intensity > y_max) {
      y_max = intensity;
    }
    if (intensity < y_min) {
      y_min = intensity;
    }
  }
  double alpha = 0.1;
  double padding = 0.025;
  NetpbmImage_draw_lineplot(&figure, ax, x, y, N, (RGB16){255, 0, 0}, 5, alpha,
                            padding);
  free(x);
  free(y);
  char title[255];
  sprintf(title, "PERFIL DE INTENSIDADE (min=%hu,max=%hu)", y_min, y_max);
  NetpbmImage_draw_string(
      &figure, (Point2D){width * 0.15, height * 0.085},
      title, (RGB16){0, 0, 0}, 3);
  NetpbmImage_show(&figure);
  NetpbmImage_save(&figure, filepath_output_graph);
  NetpbmImage_close(&figure);
  NetpbmImage_close(&img);
}
