module PGM
  ( writeImagePGM,
    readImagePGM,
  )
where

import Control.Monad
import Data.Char (isSpace)
import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as C8
import Data.Vector.Unboxed qualified as U
import Data.Word
import Matrix (Matrix (..))

writeImagePGM :: FilePath -> Matrix Word8 -> IO ()
writeImagePGM path (Matrix rows cols elems) = do
  let header =
        C8.pack $
          "P5\n"
            ++ show cols
            ++ " "
            ++ show rows
            ++ "\n"
            ++ "255\n"
  let payload = B.pack (U.toList elems)

  B.writeFile path (header <> payload)

readImagePGM :: FilePath -> IO (Either String (Matrix Word8))
readImagePGM path = do
  bs <- B.readFile path
  pure (parsePGM bs)

parsePGM :: B.ByteString -> Either String (Matrix Word8)
parsePGM bs0 = do
  (magic, r1) <- nextToken bs0
  when (magic /= "P5") $
    Left "Invalid PGM: expected magic number P5"
  (w_token, r2) <- nextToken r1
  (h_token, r3) <- nextToken r2
  (m_token, r4) <- nextToken r3
  w <- readPositiveInt w_token
  h <- readPositiveInt h_token
  m <- readPositiveInt m_token
  when
    (m /= 255)
    $ Left
      "Unsupported PGM: only maxval=255 is supported"

  let payload = skipSpaceAndComments r4
      expected = w * h
      actual = B.length payload
  when (actual /= expected) $
    Left $
      "Invalid PGM: not enough pixel data (expected "
        ++ show expected
        ++ ", got "
        ++ show actual
        ++ ")"
  Right (Matrix h w (U.fromList $ B.unpack $ B.take expected payload))

nextToken :: B.ByteString -> Either String (String, B.ByteString)
nextToken bs =
  if B.null s
    then Left "Unexpected end of file while reading header"
    else
      let (tok, rest) = B.span (not . isSpaceWord8) s
       in Right (C8.unpack tok, rest)
  where
    s = skipSpaceAndComments bs

skipSpaceAndComments :: B.ByteString -> B.ByteString
skipSpaceAndComments bs =
  let s = B.dropWhile isSpaceWord8 bs
   in case B.uncons s of
        Just (35, rest) -> skipSpaceAndComments (dropUntilNewline rest) -- '#'
        _ -> s

dropUntilNewline :: B.ByteString -> B.ByteString
dropUntilNewline bs =
  case B.elemIndex 10 bs of -- '\n'
    Nothing -> B.empty
    Just i -> B.drop (i + 1) bs

isSpaceWord8 :: Word8 -> Bool
isSpaceWord8 = isSpace . toEnum . fromEnum

readPositiveInt :: String -> Either String Int
readPositiveInt s =
  case reads s of
    [(n, "")] | n > 0 -> Right n
    _ -> Left "Invalid PGM for reading headers"
