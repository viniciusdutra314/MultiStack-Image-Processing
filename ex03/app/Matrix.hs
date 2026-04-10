module Matrix
  ( Matrix,
    getElement,
    createMatrixWithValue,
    createMatrixWithFunc,
  )
where

import Data.Vector.Unboxed qualified as U
import Data.Word (Word)

data Matrix a = Matrix
  { matrixRows :: !Word,
    matrixCols :: !Word,
    matrixElements :: !(U.Vector a)
  }
  deriving (Show)

createMatrixWithValue :: (U.Unbox a) => (Word, Word) -> a -> Matrix a
createMatrixWithValue (rows, cols) val = Matrix rows cols (U.replicate (fromIntegral (rows * cols)) val)

unflatIndex :: Word -> Int -> (Word, Word)
unflatIndex cols index = (fromIntegral (index `div` fromIntegral (cols)), fromIntegral (index `mod` fromIntegral (cols)))

createMatrixWithFunc :: (U.Unbox a) => (Word, Word) -> ((Word, Word) -> a) -> Matrix a
createMatrixWithFunc (rows, cols) func = Matrix rows cols (U.generate size (\index -> func (unflatenCurried index)))
  where
    size = fromIntegral (rows * cols)
    unflatenCurried = unflatIndex rows

getElement :: (U.Unbox a) => Matrix a -> Word -> Word -> a
getElement (Matrix _ m elements) c r = elements U.! fromIntegral (r * m + c)
