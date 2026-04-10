module Matrix
  ( Matrix,
    Matrix (..),
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

instance (Show a, U.Unbox a) => Show (Matrix a) where
  show (Matrix rows cols elements) =
    "Matrix "
      ++ show rows
      ++ "x"
      ++ show cols
      ++ "\n"
      ++ unlines
        [ show (U.slice start len elements)
          | i <- [0 .. rows - 1],
            let start = fromIntegral (i * cols),
            let len = fromIntegral cols
        ]

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
