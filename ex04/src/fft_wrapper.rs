use ndarray::Array2;
use ndrustfft::{FftHandler, ndfft, ndifft};
use num_complex::Complex64;

pub fn gray_to_complex(img: &image::GrayImage) -> Array2<Complex64> {
    let (width, height) = img.dimensions();
    let (width, height) = (width as usize, height as usize);
    Array2::from_shape_fn((width, height), |(x, y)| {
        let image::Luma([v]) = *img.get_pixel(x as u32, y as u32);
        Complex64::new(f64::from(v), 0.0)
    })
}

fn _fft2(input: &Array2<Complex64>, inverse: bool) -> Array2<Complex64> {
    let (width, height) = input.dim();
    let mut handler_x = FftHandler::<f64>::new(width);
    let mut handler_y = FftHandler::<f64>::new(height);
    let mut tmp = Array2::<Complex64>::zeros((width, height));
    let mut out = Array2::<Complex64>::zeros((width, height));

    if inverse {
        ndifft(input, &mut tmp, &mut handler_x, 0);
        ndifft(&tmp, &mut out, &mut handler_y, 1);
    } else {
        ndfft(input, &mut tmp, &mut handler_x, 0);
        ndfft(&tmp, &mut out, &mut handler_y, 1);
    }
    out
}

pub fn fft2(input: &Array2<Complex64>) -> Array2<Complex64> {
    _fft2(input, false)
}
pub fn ifft2(input: &Array2<Complex64>) -> Array2<Complex64> {
    _fft2(input, true)
}

pub fn complex_to_logged_gray(array: &Array2<Complex64>) -> image::GrayImage {
    let (width, height) = array.dim();
    let mut img = image::GrayImage::new(width as u32, height as u32);

    let logged_magnitudes = array.mapv(|c| c.norm().ln());
    let max_mag = logged_magnitudes.iter().copied().fold(0.0_f64, f64::max);

    if max_mag == 0.0 {
        return img;
    }

    for ((x, y), &mag) in logged_magnitudes.indexed_iter() {
        let v = ((mag / max_mag) * 255.0).round() as u8;
        img.put_pixel(x as u32, y as u32, image::Luma([v]));
    }

    img
}

pub fn fftshift2(input: &Array2<Complex64>) -> Array2<Complex64> {
    let (width, height) = input.dim();
    Array2::<Complex64>::from_shape_fn((width, height), |(x, y)| {
        let nx = (x + width / 2) % width;
        let ny = (y + height / 2) % height;
        input[(nx, ny)]
    })
}
