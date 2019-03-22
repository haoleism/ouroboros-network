{-# LANGUAGE GADTs               #-}
{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-# OPTIONS_GHC -Wno-orphans #-}

module Test.Mux.Control (
      tests) where

import           Codec.CBOR.Read (deserialiseFromBytes)
import           Codec.CBOR.Write (toLazyByteString)
import qualified Codec.CBOR.FlatTerm as CBOR
import           Codec.Serialise (Serialise (..))
import qualified Data.ByteString.Char8 as BSC
import           Data.Maybe (catMaybes, mapMaybe)
import qualified Data.Text as T
import           Test.QuickCheck
import           Test.Tasty (TestTree, testGroup)
import           Test.Tasty.QuickCheck (testProperty)

import           Ouroboros.Network.Mux.Control
import           Test.Mux ( NetworkMagic (..)
                          , NetworkMagicWithBufSize (..)
                          , version0
                          , version1
                          )

tests :: TestTree
tests =
  testGroup "MuxControl"
  [ testProperty "MuxControl encode/decode"      prop_mux_encode_decode
  , testProperty "MuxControl decoding"           prop_decode_ControlMsg
  , testGroup "generators"
     [ testProperty "ArbitraryFlatTerm is valid"        prop_ArbitraryFlatTerm
     , testProperty "shrink ArbitraryFlatTerm is valid" prop_shrink_ArbitraryFlatTerm
     , testProperty "shrink ArbitrarySomeVersionPair is valid" prop_shrink_ArbitrarySomeVersionPair
     ]
  ]

instance Arbitrary SomeVersion where
    arbitrary = do
        nm <- arbitrary
        s  <- arbitrary
        elements [ SomeVersion SNat0 (NetworkMagic nm)
                 , SomeVersion SNat1 (NetworkMagicWithBufSize nm s)
                 ]

instance Arbitrary ControlMsg where
    arbitrary = do
        vs <- arbitrary
        v  <- arbitrary
        f  <- arbitrary
        elements [ MsgInitReq vs
                 , MsgInitRsp v
                 , MsgInitFail f]

-- | Verify that decoder . encoder = id for ControlMsg.
prop_mux_encode_decode :: ControlMsg
                       -> Property
prop_mux_encode_decode msg =
    let bs = toLazyByteString $ encodeControlMsg msg
        res_e = deserialiseFromBytes
                  (decodeControlMsg
                      -- TODO: generate these
                      [ SomeVersion SNat0 (NetworkMagic 0)
                      , SomeVersion SNat1 (NetworkMagicWithBufSize 0 10)
                      ])
                  bs
    in case res_e of
         Left  e   -> counterexample (show e) False
         Right res -> return msg === res

-- |
-- A pair of SomeVersion and its encoding as a pair (using @'encodeAsPair'@)
-- If the generated @'CBOR.FlatTerm'@ does not correspond to some
-- @'SomeVersion@' then the first field is @'Nothing'@.
--
data ArbitraryVersionFT = ArbitraryVersionFT (Maybe SomeVersion) CBOR.FlatTerm
    deriving Show

instance Arbitrary ArbitraryVersionFT where

  arbitrary = oneof
      [ (\v -> ArbitraryVersionFT (Just v) (encodeAsPair v)) <$> arbitrary
      , do
          x <- resize 10 arbitrary
          let r = toArbitraryVersionFT (unArbitrarySomeVersionPair x)
          return r
      ]
    where
      toArbitraryVersionFT :: CBOR.FlatTerm -> ArbitraryVersionFT
      toArbitraryVersionFT t = ArbitraryVersionFT (toVersion t) t

      toVersion [CBOR.TkInt 0, CBOR.TkInt y] | y >= 0 =
        Just (SomeVersion SNat0 (NetworkMagic (fromIntegral y)))
      toVersion [CBOR.TkInt 1, CBOR.TkListLen 2, CBOR.TkInt y, CBOR.TkInt w] | y >= 0 =
        Just (SomeVersion SNat1 (NetworkMagicWithBufSize (fromIntegral y) (fromIntegral w)))
      toVersion _ = Nothing

encodeAsPair :: SomeVersion -> CBOR.FlatTerm
encodeAsPair (SomeVersion SNat0 nm) =
  CBOR.toFlatTerm $ encode (versionNumber SNat0) <> encode nm
encodeAsPair (SomeVersion SNat1 nm) =
  CBOR.toFlatTerm $ encode (versionNumber SNat1) <> encode nm
encodeAsPair _ = []

-- |
-- Generate arbitrary valid @'CBOR.FlatTerm'@.  It needs to be resized so it
-- does not loop to deep.
--
genArbitraryFlatTerm :: Gen CBOR.FlatTerm
genArbitraryFlatTerm = sized $ \s ->
  let s' = if s > 0 then pred s else 0
  in oneof
    [ (:[]) . CBOR.TkInt <$> arbitrary
    , (:[]) . CBOR.TkInteger <$> arbitrary
    , (\x  -> [CBOR.TkBytesBegin, CBOR.TkBytes x, CBOR.TkBreak]) . BSC.pack <$> arbitrary
    , (\x  -> [CBOR.TkStringBegin, CBOR.TkString x, CBOR.TkBreak]) . T.pack <$>  arbitrary
    , (\xs -> CBOR.TkListLen (fromIntegral $ length xs) : concat xs) <$> (resize s' $ listOf genArbitraryFlatTerm)
    , (\xs -> CBOR.TkListBegin : concat xs ++ [CBOR.TkBreak]) <$> (resize s' $ listOf genArbitraryFlatTerm)
    , (\xs -> CBOR.TkMapLen (fromIntegral $ length xs) : concat xs) <$> (resize s' $ listOf genArbitraryPairs)
    , (\xs -> CBOR.TkMapBegin : concat xs ++ [CBOR.TkBreak]) <$> (resize s' $ listOf genArbitraryPairs)
    , (:[]) . CBOR.TkBool <$> arbitrary
    ,  return [CBOR.TkNull]
    , (:[]) . CBOR.TkSimple <$> arbitrary
    , (:[]) . CBOR.TkFloat16 <$> arbitrary
    , (:[]) . CBOR.TkFloat32 <$> arbitrary
    , (:[]) . CBOR.TkFloat64 <$> arbitrary
    ]
  where
    genArbitraryPairs :: Gen CBOR.FlatTerm
    genArbitraryPairs = sized $ \s  ->
      let s' = if s > 0 then pred s else 0
      in (\x y -> x ++ y)
          <$> resize s' genArbitraryFlatTerm
          <*> resize s' genArbitraryFlatTerm

shrinkArbitraryFlatTerm :: CBOR.FlatTerm -> [CBOR.FlatTerm]
shrinkArbitraryFlatTerm t = filter (not . null) $ map concat $ shrinkList (const []) (splitFlatTerm t)

splitFlatTerm :: CBOR.FlatTerm -> [CBOR.FlatTerm]
splitFlatTerm (x@CBOR.TkInt{}       : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkInteger{}   : xs) = [x] : splitFlatTerm xs

splitFlatTerm (x@CBOR.TkBytesBegin  : xs) =
  let (ys, ys') = findBreak xs
  in (x : ys) : splitFlatTerm ys'
splitFlatTerm (x@CBOR.TkStringBegin : xs) =
  let (ys, ys') = findBreak xs
  in (x : ys) : splitFlatTerm ys'
splitFlatTerm (x@CBOR.TkListBegin   : xs) =
  let (ys, ys') = findBreak xs
  in (x : ys) : splitFlatTerm ys'
splitFlatTerm (x@CBOR.TkMapBegin    : xs) =
  let (ys, ys') = findBreak xs
  in (x : ys) : splitFlatTerm ys'

splitFlatTerm (x@(CBOR.TkListLen n) : xs) =
  let (ys, ys') = splitAt (fromIntegral n) (splitFlatTerm xs)
  in (x : concat ys) : ys'
splitFlatTerm (x@(CBOR.TkMapLen n)  : xs) =
  let (ys, ys') = splitAt (fromIntegral (2 * n)) (splitFlatTerm xs)
  in (x : concat ys) : ys'

splitFlatTerm (x@CBOR.TkBool{}      : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkSimple{}    : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkFloat16{}   : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkFloat32{}   : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkFloat64{}   : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkTag{}       : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkNull{}      : xs) = [x] : splitFlatTerm xs
splitFlatTerm (x@CBOR.TkBytes{}     : xs) = case splitFlatTerm xs of
  []   -> [[x]]
  y:ys -> (x:y) : ys
splitFlatTerm (x@CBOR.TkString{}    : xs) = case splitFlatTerm xs of
  []   -> [[x]]
  y:ys -> (x:y) : ys
splitFlatTerm (CBOR.TkBreak{}       : xs) = [CBOR.TkBreak] : splitFlatTerm xs
splitFlatTerm []                          = []

-- |
-- Find matching @'CBOR.TkBreak'@
--
findBreak :: CBOR.FlatTerm -> (CBOR.FlatTerm, CBOR.FlatTerm)
findBreak = go 0 []
    where
      go :: Int
         -> CBOR.FlatTerm
         -> CBOR.FlatTerm
         -> (CBOR.FlatTerm, CBOR.FlatTerm)
      go  _ !acc []                          = (reverse acc, [])
      go  0 !acc (x@CBOR.TkBreak       : xs) = (reverse (x : acc), xs)
      go !n !acc (x@CBOR.TkBreak       : xs) = go (n - 1) (x : acc) xs
      go !n !acc (x@CBOR.TkBytesBegin  : xs) = go (n + 1) (x : acc) xs
      go !n !acc (x@CBOR.TkStringBegin : xs) = go (n + 1) (x : acc) xs
      go !n !acc (x@CBOR.TkListBegin   : xs) = go (n + 1) (x : acc) xs
      go !n !acc (x@CBOR.TkMapBegin    : xs) = go (n + 1) (x : acc) xs
      go !n !acc (x                    : xs) = go n       (x : acc) xs

data ArbitraryFlatTerm = ArbitraryFlatTerm { unArbitraryFlatTerm :: CBOR.FlatTerm }
    deriving Show

instance Arbitrary ArbitraryFlatTerm where
    arbitrary = resize 10 $ ArbitraryFlatTerm <$> genArbitraryFlatTerm
    shrink = map ArbitraryFlatTerm . shrinkArbitraryFlatTerm . unArbitraryFlatTerm

prop_ArbitraryFlatTerm :: ArbitraryFlatTerm -> Property
prop_ArbitraryFlatTerm (ArbitraryFlatTerm t) =
      tabulate "Length of terms"
        [lengthLabel (length t)] $
      tabulate "FlatTerms" (labelFlatTerm t) $
        CBOR.validFlatTerm t
    where
      -- not surprisingly most of the generated cases are very short, and there
      -- are some which are very long
      lengthLabel l | l < 1  = "0"
                    | l < 2  = "1"
                    | l < 5  = "2 - 4"
                    | l < 10 = "5 - 9"
                    | l < 20 = "10 - 19"
                    | l < 40 = "20 - 39"
                    | l < 80 = "40 - 79"
                    | l < 160 = "80 - 179"
                    | otherwise = ">160"

      labelFlatTerm [] = []
      labelFlatTerm (CBOR.TkInt{}       : xs) = "TkInt" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkInteger{}   : xs) = "TkInteger" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkBytesBegin  : xs) = "TkBytesBegin" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkStringBegin : xs) = "TkStringBegin" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkListBegin   : xs) = "TkListBegin" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkMapBegin    : xs) = "TkMapBegin" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkListLen{}   : xs) = "TkListLen" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkMapLen{}    : xs) = "TkMapLen" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkBool{}      : xs) = "TkBool" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkSimple{}    : xs) = "TkSimple" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkFloat16{}   : xs) = "TkFloat16" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkFloat32{}   : xs) = "TkFloat32" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkFloat64{}   : xs) = "TkFloat64" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkTag{}       : xs) = "TkTag" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkNull{}      : xs) = "TkNull" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkBytes{}     : xs) = "TkBytes" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkString{}    : xs) = "TkString" : labelFlatTerm xs
      labelFlatTerm (CBOR.TkBreak{}     : xs) = "TkBreak" : labelFlatTerm xs

prop_shrink_ArbitraryFlatTerm :: ArbitraryFlatTerm -> Bool
prop_shrink_ArbitraryFlatTerm (ArbitraryFlatTerm t) = all CBOR.validFlatTerm (shrinkArbitraryFlatTerm t)

-- |
-- Generates valid, but possibly unknown versions.  A version is encoded as
-- a pair, a Word representing the version number and a CBOR.Term
--
genSomeVersionPair :: Gen CBOR.FlatTerm
genSomeVersionPair = oneof
    [ -- NetworkMagic case
      encodeAsPair . SomeVersion SNat0 <$> arbitrary
    , -- NetworkMagicWithBufSize case
      encodeAsPair . SomeVersion SNat1 <$> arbitrary
    , do
        -- unknown version
        NonNegative k <- arbitrary
        t <- genArbitraryFlatTerm
        return $ CBOR.TkInt (k + 2) : t
    ]

data ArbitrarySomeVersionPair = ArbitrarySomeVersionPair {
      unArbitrarySomeVersionPair :: CBOR.FlatTerm
    }
    deriving Show

instance Arbitrary ArbitrarySomeVersionPair where
    arbitrary = resize 10 $ ArbitrarySomeVersionPair <$> genSomeVersionPair

    shrink (ArbitrarySomeVersionPair (CBOR.TkInt k : ts)) = map (ArbitrarySomeVersionPair . (CBOR.TkInt k :)) (shrinkArbitraryFlatTerm ts)
    shrink _ = []


isValidTermPair :: CBOR.FlatTerm -> Bool
isValidTermPair (CBOR.TkInt _ : t) = CBOR.validFlatTerm t
isValidTermPair _                  = False

prop_shrink_ArbitrarySomeVersionPair
  :: ArbitrarySomeVersionPair
  -> Bool
prop_shrink_ArbitrarySomeVersionPair a = all (isValidTermPair . unArbitrarySomeVersionPair) (shrink a)

data ArbitraryControlMsgFT = ArbitraryControlMsgFT (Maybe ControlMsg) CBOR.FlatTerm
    deriving Show

-- |
-- The arbitrary instance which generates a @'ControlMessage@' encoding (and
-- possible message from which it was generated).  All the generated CBOR terms
-- are valid; the generator will include unknown encodings of @'Mx.Version'@.
--
instance Arbitrary ArbitraryControlMsgFT where
    arbitrary = oneof
        [ (\x -> ArbitraryControlMsgFT (Just x) (CBOR.toFlatTerm $ encodeControlMsg x)) <$> arbitrary
        , msgInitReq <$> listOf arbitrary
        , msgInitRsp <$> arbitrary
        , invalidControlMsgTag
        ]
      where
        -- |
        -- Generate @'MsgInitReq'@ with a list of versions which includes unknown
        -- terms.
        msgInitReq :: [ArbitraryVersionFT] -> ArbitraryControlMsgFT
        msgInitReq xs =
          let ts :: CBOR.FlatTerm
              ts = concatMap (\(ArbitraryVersionFT _ t) -> t) xs
              vs :: [SomeVersion]
              vs = mapMaybe (\(ArbitraryVersionFT v _) -> v) xs
          in ArbitraryControlMsgFT
            (Just (MsgInitReq vs))
            (CBOR.TkListLen 2
              : CBOR.TkInt 0
              : CBOR.TkMapLen (fromIntegral $ length xs)
              : ts)

        -- |
        -- Generate @'MsgInitRsp'@ which includes unknown term.
        msgInitRsp :: ArbitraryVersionFT -> (ArbitraryControlMsgFT)
        msgInitRsp (ArbitraryVersionFT (Just v) _) =
          ArbitraryControlMsgFT
            (Just (MsgInitRsp v))
            (CBOR.toFlatTerm $ encodeControlMsg (MsgInitRsp v))
        msgInitRsp (ArbitraryVersionFT Nothing ts) =
          ArbitraryControlMsgFT
            Nothing
            (CBOR.TkListLen 2
              : CBOR.TkInt 1
              : ts)

        -- |
        -- Generate @'ControlMsg'@ with an unknown tag, which includes
        -- unknown terms.
        invalidControlMsgTag :: Gen (ArbitraryControlMsgFT)
        invalidControlMsgTag = do
          Positive x <- arbitrary
          (xs :: [CBOR.FlatTerm]) <- listOf (unArbitraryFlatTerm <$> arbitrary)
          return $ ArbitraryControlMsgFT Nothing
            (CBOR.TkListLen (fromIntegral $ (length xs) + 1)
              : CBOR.TkInt (x + 2)
              : concat xs)

    -- this shrinking is not good enough, we should shrink simultaneously `vs`
    -- and `ts`, but this is slightly difficult.
    shrink (ArbitraryControlMsgFT (Just (MsgInitReq vs)) ts)
      = [ ArbitraryControlMsgFT (Just (MsgInitReq vs')) (CBOR.toFlatTerm $ encodeControlMsg (MsgInitReq vs'))
        | vs' <- shrinkList (const []) vs
        ]
        ++
        [ ArbitraryControlMsgFT Nothing ts'
        | ts' <- shrinkArbitraryFlatTerm ts
        ]
        ++
          case ts of
            CBOR.TkListLen a : CBOR.TkInt b : CBOR.TkListLen _ : xs ->
              [ ArbitraryControlMsgFT
                  (Just (MsgInitReq $ catMaybes $ map fst xs'))
                  (CBOR.TkListLen a : CBOR.TkInt b : CBOR.TkListLen (fromIntegral $ length xs') : concat (map snd xs'))
              | xs' <- shrinkList (const []) $ zip' (CBOR.toFlatTerm . encodeSomeVersion) vs (splitFlatTerm xs)
              ]
            _ -> []
      where
        zip' :: Eq b => (a -> b) -> [a] -> [b] -> [(Maybe a, b)]
        zip' f (a:as) (b:bs) =
          if f a == b
          then (Just a, b)  : zip' f as bs
          else (Nothing, b) : zip' f (a:as) bs
        zip' _ []     _      = []
        zip' _ _      []     = []


    shrink (ArbitraryControlMsgFT (Just _) _) = []
    shrink (ArbitraryControlMsgFT Nothing ts) = map (ArbitraryControlMsgFT Nothing) (shrinkArbitraryFlatTerm ts)

-- |
-- Check that we can decode all version that we know ignoring version's that
-- are unknown.
--
prop_decode_ControlMsg :: ArbitraryControlMsgFT
                       -> Property
prop_decode_ControlMsg (ArbitraryControlMsgFT msg t) =
      tabulate "Decode successful" [resLabel] $
      tabulate "Does ControlMsg agrees with CBOR term?" [labelArbCtrlMsg msg t] $
        case res of
          Left e     -> counterexample (show e) $ maybe True (const False) msg
          Right msg' -> msg === Just msg'
    where
      res = CBOR.fromFlatTerm (decodeControlMsg [version0, version1]) t

      labelArbCtrlMsg (Just a) ts | CBOR.toFlatTerm (encodeControlMsg a) == ts
                                  = "agrees"
                                  | otherwise
                                  = "not agrees"
      labelArbCtrlMsg Nothing  _  = "arbitrary cborg term"

      resLabel = case res of
        Left{}  -> "False"
        Right{} -> "True"
