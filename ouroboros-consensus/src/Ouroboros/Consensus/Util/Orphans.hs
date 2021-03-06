{-# OPTIONS_GHC -fno-warn-orphans #-}
module Ouroboros.Consensus.Util.Orphans () where

import           Control.Monad.Identity
import           Control.Monad.Trans
import           Crypto.Random

import           Ouroboros.Network.Block (SlotNo (..))
import           Ouroboros.Network.Chain (Chain (..))

import           Ouroboros.Consensus.Util.Condense

{-------------------------------------------------------------------------------
  Condense
-------------------------------------------------------------------------------}

instance Condense SlotNo where
  condense (SlotNo n) = condense n

instance Condense block => Condense (Chain block) where
    condense Genesis   = "Genesis"
    condense (cs :> b) = condense cs <> " :> " <> condense b

{-------------------------------------------------------------------------------
  MonadRandom
-------------------------------------------------------------------------------}

instance MonadRandom m => MonadRandom (IdentityT m) where
     getRandomBytes = lift . getRandomBytes
