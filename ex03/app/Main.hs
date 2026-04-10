{-# LANGUAGE LambdaCase #-}

import Data.Word
import Matrix
import PGM

checkboard :: Matrix Word8
checkboard =
  createMatrixWithFunc
    (size, size)
    ( \case
        (i, j)
          | sameSide i j -> black
          | otherwise -> white
    )
  where
    sameSide i j = (i < mid && j < mid) || (i >= mid && j >= mid)
    white = 255
    black = 0
    size = 512
    mid = size `div` 2

-- meanKernel :: Array U Ix2 Double
-- meanKernel = makeArray Seq (Sz (30 :. 30)) (\_ -> 1.0 / (30.0 * 30.0))

-- blurStencil = makeConvolutionStencilFromKernel meanKernel

-- blurConvolution = mapStencil (Fill 0) blurStencil

main :: IO ()
main = do
  writeImagePGM "checkboard.pgm" checkboard
