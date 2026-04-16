use std::error::Error;
pub mod fft_wrapper;
use fft_wrapper::*;
use ndarray::Array2;
use ndrustfft::Zero;
use num_complex::{Complex64, ComplexFloat};

fn main() -> Result<(), Box<dyn Error>> {
    // Crie as pastas para as questões
    for n in 1..=13 {
        std::fs::create_dir_all(format!("questao_{n:02}"))?;
    }

    // Questão 01
    let img = image::open("img_examples/forest_gray.jpg")?.into_luma8();
    let img_complex = gray_to_complex(&img);
    let img_fft = fft2(&img_complex);
    complex_to_logged_gray(&(fftshift2(&img_fft))).save("questao_01/fft_img.jpg")?;
    // Questão 02
    let img_fft_ifft = ifft2(&img_fft);
    complex_to_clamped_gray(&img_fft_ifft).save("questao_02/img_fft_ifft.jpg")?;
    let diff_img_vs_img_fft_ifft = img_complex.clone() - img_fft_ifft;
    let min_diff = diff_img_vs_img_fft_ifft
        .iter()
        .min_by(|a, b| a.norm().partial_cmp(&b.norm()).unwrap())
        .unwrap();
    println!("Min diff: {}", min_diff.norm());
    let max_diff = diff_img_vs_img_fft_ifft
        .iter()
        .max_by(|a, b| a.norm().partial_cmp(&b.norm()).unwrap())
        .unwrap();
    println!("Max diff: {}", max_diff.norm());

    complex_to_clamped_gray(&diff_img_vs_img_fft_ifft)
        .save("questao_02/diff_img_vs_img_fft_ifft.jpg")?;
    //
    // Questão 3
    let img_fft_shift_ifft = ifft2(&fftshift2(&(img_fft)));
    complex_to_clamped_gray(&img_fft_shift_ifft).save("questao_03/img_fft_shift_ifft.jpg")?;

    // Questão 4
    let img_fft_center_zeroed = Array2::<Complex64>::from_shape_fn(img_fft.dim(), |(x, y)| {
        if (x, y) == (0, 0) {
            Complex64::zero()
        } else {
            img_fft[(x, y)]
        }
    });

    let img_fft_zeroed_center_ifft = ifft2(&img_fft_center_zeroed);
    complex_to_clamped_gray(&img_fft_zeroed_center_ifft)
        .save("questao_04/img_fft_zeroed_center_ifft.jpg")?;
    let img_mean_pixel = img_complex.mean().unwrap().re();
    let img_subtract_avg = image::GrayImage::from_fn(img.width(), img.height(), |x, y| {
        let v = img.get_pixel(x, y)[0] as f64 - img_mean_pixel;
        image::Luma([clamp(0.0, 255.0, v) as u8])
    });
    img_subtract_avg.save("questao_04/img_removed_avg.jpg")?;
    Ok(())
}
