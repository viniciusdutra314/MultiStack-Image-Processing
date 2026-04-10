module PGM
  ( writeImagePGM,
  )
where

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as C8
import qualified Data.Vector.Unboxed as U
import Data.Word
import Matrix (Matrix (..))

writeImagePGM :: FilePath -> Matrix Word8 -> IO ()
writeImagePGM path (Matrix rows cols elems) = do
  let w = fromIntegral cols :: Int
      h = fromIntegral rows :: Int
  let header =
        C8.pack $
          "P5\n"
            ++ show w
            ++ " "
            ++ show h
            ++ "\n"
            ++ "255\n"
  let payload = B.pack (U.toList elems)

  B.writeFile path (header <> payload)
