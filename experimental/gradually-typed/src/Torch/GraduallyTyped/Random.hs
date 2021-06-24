{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Torch.GraduallyTyped.Random (Generator, noGenerator, mkGenerator, checkedGenerator, uncheckedGenerator, withGenerator) where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Data.Int (Int16)
import Data.Word (Word64)
import Foreign.ForeignPtr (ForeignPtr)
import GHC.TypeLits (Nat)
import System.IO.Unsafe (unsafePerformIO)
import Torch.GraduallyTyped.Device (Device (..), DeviceType (..), KnownDeviceType, SDevice, WithDeviceC (..))
import qualified Torch.Internal.Managed.Type.Generator as ATen
import qualified Torch.Internal.Type as ATen

data Generator (device :: Device (DeviceType Nat)) where
  UnsafeGenerator ::
    forall device.
    { generatorSeed :: Word64,
      generatorDeviceType :: DeviceType Int16,
      generatorState :: TVar (Maybe (ForeignPtr ATen.Generator))
    } ->
    Generator device
  NoGenerator :: forall device. Generator device

type role Generator nominal

noGenerator :: forall device. Generator device
noGenerator = NoGenerator

mkGenerator ::
  forall device.
  (WithDeviceC device (Word64 -> IO (Generator device))) =>
  WithDeviceF device (Word64 -> IO (Generator device))
mkGenerator =
  withDevice @device go
  where
    go device seed = case device of
      CPU -> do
        genPtr <- ATen.newCPUGenerator seed
        genenerator <- newTVarIO (Just genPtr)
        return $ UnsafeGenerator @device seed device genenerator
      CUDA deviceId -> do
        genPtr <- ATen.newCUDAGenerator (fromIntegral deviceId)
        ATen.generator_set_current_seed genPtr seed
        genenerator <- newTVarIO (Just genPtr)
        return $ UnsafeGenerator @device seed device genenerator

sMkGenerator ::
  forall device.
  SDevice device ->
  Word64 ->
  IO (Generator device)
sMkGenerator device =
  case sDeviceType device of
    CPU -> do
      genPtr <- ATen.newCPUGenerator seed
      genenerator <- newTVarIO (Just genPtr)
      return $ UnsafeGenerator @device seed device genenerator
    CUDA deviceId -> do
      genPtr <- ATen.newCUDAGenerator (fromIntegral deviceId)
      ATen.generator_set_current_seed genPtr seed
      genenerator <- newTVarIO (Just genPtr)
      return $ UnsafeGenerator @device seed device genenerator

withGenerator ::
  forall a device.
  (ForeignPtr ATen.Generator -> IO a) ->
  a ->
  Generator device ->
  (a, Generator device)
withGenerator _ a NoGenerator = (a, NoGenerator)
withGenerator f _ UnsafeGenerator {..} = unsafePerformIO $ do
  mGenPtr <- atomically $ do
    mGenPtr <- readTVar generatorState
    case mGenPtr of
      Just genPtr -> do
        writeTVar generatorState Nothing
        return $ Just genPtr
      Nothing -> return Nothing
  genPtr <- case mGenPtr of
    Just genPtr -> return genPtr
    Nothing -> case generatorDeviceType of
      CPU -> ATen.newCPUGenerator generatorSeed
      CUDA deviceId -> do
        genPtr <- ATen.newCUDAGenerator (fromIntegral deviceId)
        ATen.generator_set_current_seed genPtr generatorSeed
        return genPtr
  a <- f genPtr
  nextSeed <- ATen.generator_current_seed genPtr
  nextGen <- newTVarIO (Just genPtr)
  return (a, UnsafeGenerator nextSeed generatorDeviceType nextGen)
