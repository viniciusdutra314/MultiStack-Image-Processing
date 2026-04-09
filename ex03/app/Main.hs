module Main where

import Codec.Picture

main :: IO ()
main = do
  res <- readImage "/home/vinicius/github/ImageProcessing/isolar.pgm"
  case res of
    Left err -> putStrLn $ "Error loading image: " ++ err
    Right image -> putStrLn "Success! Image opened."
