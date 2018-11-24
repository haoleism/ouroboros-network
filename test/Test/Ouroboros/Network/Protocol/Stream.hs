{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
module Test.Ouroboros.Network.Protocol.Stream where

-- TODO: add test which uses `Protocol.Core.connect`

import           Control.Monad (join)
import           Control.Monad.ST.Lazy (runST)
import           Numeric.Natural (Natural)
import           Pipes (yield)

import           Test.QuickCheck
import           Test.Tasty (TestTree, testGroup)
import           Test.Tasty.QuickCheck (testProperty)

import Ouroboros.Network.MonadClass (MonadProbe (..), MonadRunProbe (..), MonadSTM (..), fork, withProbe)

import Ouroboros.Network.Protocol.Stream.Client
import Ouroboros.Network.Protocol.Stream.Server
import Ouroboros.Network.Protocol.Stream.Direct

tests :: TestTree
tests =
  testGroup "Ouroboros.Network.Protocol.Stream"
  [ testProperty "directIO" prop_direct_IO
  , testProperty "directSim" prop_direct_Sim
  ]

listStreamServer
  :: Monad m
  => StreamServer m (Int, Int) Int (Maybe [Int])
listStreamServer = streamServer (Right . go [])
 where
  go acc (x, y) | x >= y    = yield x >> return (Just (x:acc))
                | otherwise = yield x >> go (x:acc) (succ x, y)

newtype Window = Window Natural
  deriving (Eq, Show)

instance Arbitrary Window where
  arbitrary = do
    Positive x <- arbitrary @(Positive Int)
    return $ Window (fromIntegral x)

readQueue :: MonadSTM m => TBQueue m (StreamElement a) -> m [a]
readQueue queue = go []
 where
  go acc = do
    r <- atomically $ readTBQueue queue
    case r of
      EndOfStream{}   -> return acc
      StreamElement a -> go (a : acc)

-- | Transfer a request a list of integers from a server and check that the
-- results received by the client are the same as the one generated by the
-- server.
--
test_direct
  :: forall m n.
     ( MonadSTM m
     , MonadProbe m
     , MonadRunProbe m n
     )
  => Window
  -> (Int, Int)
  -> n Property
test_direct (Window window) range = snd . head <$> withProbe experiment
 where
  experiment :: Probe m Property -> m ()
  experiment probe = do
    queue <- atomically $ newTBQueue window
    let client = streamClient queue range
    var <- atomically $ newTVar Nothing
    fork $ do
      res <- fst <$> direct listStreamServer client
      atomically $ writeTVar var (Just res)
    cliRes <- readQueue queue
    serRes <- join <$> atomically (readTVar var)
    probeOutput probe (Just cliRes === serRes)

prop_direct_IO :: Window -> (Int, Int) -> Property
prop_direct_IO window range = ioProperty (test_direct window range)

prop_direct_Sim :: Window -> (Int, Int) -> Property
prop_direct_Sim window range = runST $ test_direct window range
