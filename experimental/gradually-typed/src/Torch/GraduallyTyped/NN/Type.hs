{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module Torch.GraduallyTyped.NN.Type where

import Data.Singletons.TH (genSingletons)
import GHC.Generics (Generic)

data HasBias = WithBias | WithoutBias
  deriving stock (Eq, Ord, Show, Generic)

genSingletons [''HasBias]
