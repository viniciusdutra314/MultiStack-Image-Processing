{-# LANGUAGE LambdaCase #-}

import Data.Word
import Matrix

-- import Data.Massiv.Array as A
-- import Data.Massiv.Array.IO
-- import Data.Massiv.Array.Stencil
-- import Matrix

-- type GrayPixel = Pixel (Y D65)

-- type GrayU8 = GrayPixel Word8

-- type GrayF32 = GrayPixel Float

-- imgToDouble :: Array U Ix2 GrayU8 -> Array D Ix2 GrayF32
-- imgToDouble = A.map (fmap fromIntegral)

checkboard :: Matrix Word8
checkboard =
  createMatrixWithFunc
    (512, 512)
    ( \case
        (i, j)
          | sameSide i j -> black
          | otherwise -> white
    )
  where
    sameSide i j = (i < mid && j < mid) || (i >= mid && j >= mid)
    white = 255
    black = 0
    mid = 512 `div` 2

-- meanKernel :: Array U Ix2 Double
-- meanKernel = makeArray Seq (Sz (30 :. 30)) (\_ -> 1.0 / (30.0 * 30.0))

-- blurStencil = makeConvolutionStencilFromKernel meanKernel

-- blurConvolution = mapStencil (Fill 0) blurStencil

main :: IO ()
main = do
  print checkboard
