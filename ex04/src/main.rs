use std::error::Error;
pub mod fft_wrapper;
use fft_wrapper::*;
use ndarray::Array2;
use ndrustfft::Zero;
use num_complex::{Complex64, ComplexFloat};

fn main() -> Result<(), Box<dyn Error>> {
    // Crie as pastas para as questões
    for n in 1..=13 {
        let path = format!("questao_{n:02}");
        std::fs::remove_dir_all(&path)?;
        std::fs::create_dir_all(&path)?;
    }

    // Questão 01
    let img = image::open("img_examples/jessica_gray.jpg")?.into_luma8();
    let (width, height) = img.dimensions();
    let (width, height) = (width as usize, height as usize);
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
    println!("Questão 02:");
    println!("  Diferença mínima: {:E}", min_diff.norm());
    let max_diff = diff_img_vs_img_fft_ifft
        .iter()
        .max_by(|a, b| a.norm().partial_cmp(&b.norm()).unwrap())
        .unwrap();
    println!("  Diferença máxima: {:E}", max_diff.norm());

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
    // Questão 05
    let img_fft_odd_lines_zeroed = Array2::<Complex64>::from_shape_fn(img_fft.dim(), |(x, y)| {
        if y % 2 == 1 {
            Complex64::zero()
        } else {
            img_fft[(x, y)]
        }
    });

    complex_to_logged_gray(&img_fft_odd_lines_zeroed)
        .save("questao_05/fft_odd_lines_zeroed.jpg")?;

    let img_fft_odd_lines_zeroed_ifft = ifft2(&img_fft_odd_lines_zeroed);
    complex_to_clamped_gray(&img_fft_odd_lines_zeroed_ifft)
        .save("questao_05/img_ifft_odd_lines_zeroed.jpg")?;

    println!(
        "Questão 05:\n  dimensão da imagem obtida: {:?}",
        img_fft_odd_lines_zeroed_ifft.shape()
    );
    // Questão 6
    let img_fft_five_lines_on_and_zeroed =
        Array2::<Complex64>::from_shape_fn(img_fft.dim(), |(x, y)| {
            if y % 10 > 5 {
                Complex64::zero()
            } else {
                img_fft[(x, y)]
            }
        });
    complex_to_logged_gray(&img_fft_five_lines_on_and_zeroed)
        .save("questao_06/fft_five_lines_on_and_off.jpg")?;
    let img_fft_five_on_and_off_ifft = ifft2(&img_fft_five_lines_on_and_zeroed);
    complex_to_clamped_gray(&img_fft_five_on_and_off_ifft)
        .save("questao_06/img_ifft_five_lines_on_and_off.jpg")?;
    // Questão 7
    let img_fft_even_lines =
        Array2::<Complex64>::from_shape_fn((width, height / 2), |(x, y)| img_fft[(x, 2 * y)]);
    complex_to_logged_gray(&img_fft_even_lines).save("questao_07/img_fft_even_lines.jpg")?;
    let img_fft_even_lines_ifft = ifft2(&img_fft_even_lines);
    complex_to_clamped_gray(&img_fft_even_lines_ifft)
        .save("questao_07/img_fft_even_lines_ifft.jpg")?;
    println!(
        "Questão 07:\n   dimensão da imagem obtida: {:?}",
        img_fft_even_lines.shape()
    );
    // Questão 8
    let img_fft_even_columns =
        Array2::<Complex64>::from_shape_fn((width / 2, height), |(x, y)| img_fft[(2 * x, y)]);
    complex_to_logged_gray(&img_fft_even_columns).save("questao_08/img_fft_even_columns.jpg")?;
    let img_fft_even_columns_ifft = ifft2(&img_fft_even_columns);
    complex_to_clamped_gray(&img_fft_even_columns_ifft)
        .save("questao_08/img_fft_even_columns_ifft.jpg")?;
    println!(
        "Questão 08:\n   dimensão da imagem obtida: {:?}",
        img_fft_even_columns.shape()
    );
    // Questão 9
    let img_fft_even_lines_and_columns =
        Array2::<Complex64>::from_shape_fn((width / 2, height / 2), |(x, y)| {
            img_fft[(2 * x, 2 * y)]
        });
    complex_to_logged_gray(&img_fft_even_lines_and_columns)
        .save("questao_09/img_fft_even_lines_and_columns.jpg")?;
    let img_fft_five_on_and_removed_ifft = ifft2(&img_fft_even_lines_and_columns);
    complex_to_clamped_gray(&img_fft_five_on_and_removed_ifft)
        .save("questao_09/img_fft_five_on_and_removed_ifft.jpg")?;
    println!(
        "Questão 09:\n   dimensão da imagem obtida: {:?}",
        img_fft_even_lines_and_columns.shape()
    );
    Ok(())
}
