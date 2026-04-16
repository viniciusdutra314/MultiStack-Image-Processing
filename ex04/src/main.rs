use std::error::Error;
pub mod fft_wrapper;
use fft_wrapper::*;

fn main() -> Result<(), Box<dyn Error>> {
    let img = image::open("photo.jpg")?.into_luma8();

    let img_complex = gray_to_complex(&img);
    let img_fft = fft2(&img_complex);
    complex_to_logged_gray(&(fftshift2(&img_fft))).save("spectrum.jpg")?;

    Ok(())
}
