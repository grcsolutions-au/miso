-----------------------------------------------------------------------------
{-# LANGUAGE CPP               #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DerivingVia       #-}
{-# LANGUAGE StandaloneDeriving #-}
-----------------------------------------------------------------------------
{-# OPTIONS_GHC -fno-warn-orphans #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Miso.String
-- Copyright   :  (C) 2016-2026 David M. Johnson
-- License     :  BSD3-style (see the file LICENSE)
-- Maintainer  :  David M. Johnson <code@dmj.io>
-- Stability   :  experimental
-- Portability :  non-portable
--
-- The 'MisoString' type and its conversion type classes.
--
-- 'MisoString' is a platform-conditional alias:
--
-- * On the client (WASM \/ GHC JS backend) it is @JSString@ — a zero-copy
--   wrapper around a native JavaScript string, giving optimal interop with
--   the DOM and JSON APIs.
-- * On the server (@VANILLA@ build) it is 'Data.Text.Text', enabling
--   server-side rendering without any FFI dependency.
--
-- Use 'ms' (short for 'toMisoString') to convert from 'String', 'T.Text',
-- numeric types, etc. into 'MisoString'.
----------------------------------------------------------------------------
module Miso.String
  ( ToMisoString (..)
  , FromMisoString (..)
  , fromMisoString
  , MisoString
#ifdef VANILLA
  , module Data.Text
#else
  , module Data.JSString
#endif
  , ms
  ) where
----------------------------------------------------------------------------
import           Control.Exception
import           Control.Applicative (Const)
import           Data.Bifunctor (bimap)
import qualified Data.ByteString as B
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Fixed as F
import           Data.Functor.Identity (Identity)
import           Data.Int (Int8, Int16, Int32, Int64)
import           Data.Monoid (All, Any, Dual, First, Last, Product, Sum)
#ifdef VANILLA
import           Data.Text hiding (show, elem)
#else
import           Data.JSString
#ifdef GHCJS_BOTH
import           Data.JSString.Text
#endif
#endif
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LT
import qualified Data.Semigroup as Semi
import           Data.Tagged (Tagged)
import           Data.Time.Calendar.Month.Compat (Month)
import           Data.Time.Calendar.Quarter.Compat (Quarter, QuarterOfYear)
import           Data.Time.Compat (Day, DayOfWeek, LocalTime, NominalDiffTime,
                                   TimeOfDay, UTCTime, ZonedTime)
import qualified Data.UUID.Types as UUID
import           Data.Version (Version)
import           Data.Void (Void)
import           Data.Word (Word8, Word16, Word32, Word64)
import           Numeric.Natural (Natural)
----------------------------------------------------------------------------
import           Miso.DSL.FFI
----------------------------------------------------------------------------
import           Web.HttpApiData
                   ( LenientData
                   , ToHttpApiData (toUrlPiece)
                   , FromHttpApiData (parseUrlPiece)
                   )
import           Web.Cookie (SetCookie)
-----------------------------------------------------------------------------
-- | The primary string type in Miso applications.
--
-- * @VANILLA@ (server\/SSR build): alias for 'Data.Text.Text'
-- * WASM \/ GHC JS backend: alias for @JSString@ — a zero-copy wrapper around
--   a native JavaScript string, giving optimal interop with the DOM and JSON APIs
--
#ifdef VANILLA
type MisoString = Text
#else
type MisoString = JSString
#endif
----------------------------------------------------------------------------
-- | A type that can be converted to 'MisoString'.
--
-- Instances are provided for 'String', 'T.Text', 'LT.Text', 'B.ByteString',
-- 'BL.ByteString', 'Double', 'Float', 'Int', 'Word', and others.
-- Use 'ms' as a short alias for 'toMisoString'.
class ToMisoString str where
  -- | Convert a value to 'MisoString'.
  toMisoString :: str -> MisoString
----------------------------------------------------------------------------
-- | A type that can be parsed from a 'MisoString'.
-- Like a safe 'Read' that returns an error message on failure.
class FromMisoString t where
  -- | Parse a 'MisoString', returning @'Left' errMsg@ on failure.
  fromMisoStringEither :: MisoString -> Either String t
----------------------------------------------------------------------------
-- | Parse a 'MisoString', throwing an error on failure.
-- Use 'fromMisoStringEither' as a safe alternative.
fromMisoString :: FromMisoString a => MisoString -> a
fromMisoString s =
  case fromMisoStringEither s of
    Left error_ -> error ("fromMisoString: " <> error_)
    Right x  -> x
----------------------------------------------------------------------------
-- | Short alias for 'toMisoString'. The idiomatic way to construct a 'MisoString'.
ms :: ToMisoString str => str -> MisoString
ms = toMisoString
----------------------------------------------------------------------------
instance ToMisoString a => ToMisoString (Maybe a) where
  toMisoString = \case
    Nothing -> mempty
    Just x -> ms x
----------------------------------------------------------------------------
instance ToMisoString Char where
  toMisoString = singleton
----------------------------------------------------------------------------
instance ToMisoString IOException where
  toMisoString = ms . show
----------------------------------------------------------------------------
#ifndef VANILLA
instance ToMisoString MisoString where
  toMisoString = id
#endif
----------------------------------------------------------------------------
instance ToMisoString SomeException where
  toMisoString = ms . show
----------------------------------------------------------------------------
instance ToMisoString String where
  toMisoString = pack
----------------------------------------------------------------------------
instance ToMisoString LT.Text where
  toMisoString = ms . LT.toStrict
----------------------------------------------------------------------------
instance ToMisoString T.Text where
#ifdef VANILLA
  toMisoString = id
#else
  toMisoString = textToJSString
#endif
----------------------------------------------------------------------------
instance ToMisoString B.ByteString where
  toMisoString = ms . T.decodeUtf8
----------------------------------------------------------------------------
instance ToMisoString BL.ByteString where
  toMisoString = ms . LT.decodeUtf8
----------------------------------------------------------------------------
instance ToMisoString B.Builder where
  toMisoString = ms . B.toLazyByteString
----------------------------------------------------------------------------
instance ToMisoString Float where
  -- dmj: issue where Float shows additional digits (affects both JS & WASM)
  toMisoString = toString_Double . realToFrac
----------------------------------------------------------------------------
instance ToMisoString Double where
  toMisoString = toString_Double
----------------------------------------------------------------------------
instance ToMisoString Int where
  toMisoString = toString_Int
instance ToMisoString Int8 where
  toMisoString = toString_Int . fromIntegral
instance ToMisoString Int16 where
  toMisoString = toString_Int . fromIntegral
instance ToMisoString Int32 where
  toMisoString = toString_Int . fromIntegral
----------------------------------------------------------------------------
instance ToMisoString Word where
  toMisoString = toString_Word
instance ToMisoString Word8 where
  toMisoString = toString_Word . fromIntegral
instance ToMisoString Word16 where
  toMisoString = toString_Word . fromIntegral
instance ToMisoString Word32 where
  toMisoString = toString_Word . fromIntegral
----------------------------------------------------------------------------
#ifndef VANILLA
instance FromMisoString MisoString where
  fromMisoStringEither = Right
#endif
----------------------------------------------------------------------------
instance FromMisoString T.Text where
#ifdef VANILLA
  fromMisoStringEither = Right
#else
  fromMisoStringEither = Right . textFromJSString
#endif
----------------------------------------------------------------------------
instance FromMisoString String where
  fromMisoStringEither = Right . unpack
----------------------------------------------------------------------------
instance FromMisoString LT.Text where
#ifdef VANILLA
  fromMisoStringEither = Right . LT.fromStrict
#else
  fromMisoStringEither = Right . LT.fromStrict . textFromJSString
#endif
----------------------------------------------------------------------------
instance FromMisoString B.ByteString where
  fromMisoStringEither = fmap T.encodeUtf8 . fromMisoStringEither
----------------------------------------------------------------------------
instance FromMisoString BL.ByteString where
  fromMisoStringEither = fmap LT.encodeUtf8 . fromMisoStringEither
----------------------------------------------------------------------------
instance FromMisoString B.Builder where
  fromMisoStringEither = fmap B.byteString . fromMisoStringEither
----------------------------------------------------------------------------
instance FromMisoString Word where
  fromMisoStringEither string =
    case parseWord string of
      Nothing -> Left ("fromMisoString Word: could not parse " <> unpack string)
      Just x -> Right x
----------------------------------------------------------------------------
instance FromMisoString Double where
  fromMisoStringEither string =
    case parseDouble string of
      Nothing -> Left ("fromMisoString Double: could not parse " <> unpack string)
      Just x -> Right x
----------------------------------------------------------------------------
instance FromMisoString Int where
  fromMisoStringEither string =
    case parseInt string of
      Nothing -> Left ("fromMisoString Int: could not parse " <> unpack string)
      Just x -> Right x
----------------------------------------------------------------------------
instance FromMisoString Float where
  fromMisoStringEither string =
    case parseFloat string of
      Nothing -> Left ("fromMisoString Float: could not parse " <> unpack string)
      Just x -> Right x
----------------------------------------------------------------------------
newtype ViaHttpApiData a = ViaHttpApiData { unMisoViaHttpApiData :: a }
----------------------------------------------------------------------------
instance ToHttpApiData a => ToMisoString (ViaHttpApiData a) where
  toMisoString = ms . toUrlPiece . unMisoViaHttpApiData
----------------------------------------------------------------------------
instance FromHttpApiData a => FromMisoString (ViaHttpApiData a) where
  fromMisoStringEither = bimap T.unpack ViaHttpApiData . parseUrlPiece . fromMisoString
----------------------------------------------------------------------------
-- ToHttpApiData instances
deriving via (ViaHttpApiData ()) instance ToMisoString ()
deriving via (ViaHttpApiData Version) instance ToMisoString Version
deriving via (ViaHttpApiData Void) instance ToMisoString Void
deriving via (ViaHttpApiData Natural) instance ToMisoString Natural
deriving via (ViaHttpApiData Bool) instance ToMisoString Bool
deriving via (ViaHttpApiData Ordering) instance ToMisoString Ordering
-- The Int64, Word64 and Integer instances will overflow 32 bit WASM
-- and lose precision inJavascript ints (which are represented as doubles, 
-- but only have 53 bits of integer precision). 
-- So we can't use the primitive `toString_Word`. 
deriving via (ViaHttpApiData Int64) instance ToMisoString Int64
deriving via (ViaHttpApiData Integer) instance ToMisoString Integer
deriving via (ViaHttpApiData Word64) instance ToMisoString Word64
deriving via (ViaHttpApiData (F.Fixed a))
  instance F.HasResolution a => ToMisoString (F.Fixed a)
deriving via (ViaHttpApiData Day) instance ToMisoString Day
deriving via (ViaHttpApiData TimeOfDay) instance ToMisoString TimeOfDay
deriving via (ViaHttpApiData LocalTime) instance ToMisoString LocalTime
deriving via (ViaHttpApiData ZonedTime) instance ToMisoString ZonedTime
deriving via (ViaHttpApiData UTCTime) instance ToMisoString UTCTime
deriving via (ViaHttpApiData DayOfWeek) instance ToMisoString DayOfWeek
deriving via (ViaHttpApiData QuarterOfYear) instance ToMisoString QuarterOfYear
deriving via (ViaHttpApiData Quarter) instance ToMisoString Quarter
deriving via (ViaHttpApiData Month) instance ToMisoString Month
deriving via (ViaHttpApiData NominalDiffTime) instance ToMisoString NominalDiffTime
deriving via (ViaHttpApiData All) instance ToMisoString All
deriving via (ViaHttpApiData Any) instance ToMisoString Any
deriving via (ViaHttpApiData (Dual a))
  instance ToHttpApiData a => ToMisoString (Dual a)
deriving via (ViaHttpApiData (Sum a))
  instance ToHttpApiData a => ToMisoString (Sum a)
deriving via (ViaHttpApiData (Product a))
  instance ToHttpApiData a => ToMisoString (Product a)
deriving via (ViaHttpApiData (First a))
  instance ToHttpApiData a => ToMisoString (First a)
deriving via (ViaHttpApiData (Last a))
  instance ToHttpApiData a => ToMisoString (Last a)
deriving via (ViaHttpApiData (Semi.Min a))
  instance ToHttpApiData a => ToMisoString (Semi.Min a)
deriving via (ViaHttpApiData (Semi.Max a))
  instance ToHttpApiData a => ToMisoString (Semi.Max a)
deriving via (ViaHttpApiData (Semi.First a))
  instance ToHttpApiData a => ToMisoString (Semi.First a)
deriving via (ViaHttpApiData (Semi.Last a))
  instance ToHttpApiData a => ToMisoString (Semi.Last a)
deriving via (ViaHttpApiData (Either a b))
  instance (ToHttpApiData a, ToHttpApiData b) => ToMisoString (Either a b)
deriving via (ViaHttpApiData SetCookie) instance ToMisoString SetCookie
deriving via (ViaHttpApiData (Tagged b a))
  instance ToHttpApiData a => ToMisoString (Tagged b a)
deriving via (ViaHttpApiData (Const a b))
  instance ToHttpApiData a => ToMisoString (Const a b)
deriving via (ViaHttpApiData (Identity a))
  instance ToHttpApiData a => ToMisoString (Identity a)
deriving via (ViaHttpApiData UUID.UUID) instance ToMisoString UUID.UUID
----------------------------------------------------------------------------
-- FromHttpApiData instances
deriving via (ViaHttpApiData ()) instance FromMisoString ()
deriving via (ViaHttpApiData Char) instance FromMisoString Char
deriving via (ViaHttpApiData Version) instance FromMisoString Version
deriving via (ViaHttpApiData Void) instance FromMisoString Void
deriving via (ViaHttpApiData Natural) instance FromMisoString Natural
deriving via (ViaHttpApiData Bool) instance FromMisoString Bool
deriving via (ViaHttpApiData Ordering) instance FromMisoString Ordering
deriving via (ViaHttpApiData Int8) instance FromMisoString Int8
deriving via (ViaHttpApiData Int16) instance FromMisoString Int16
deriving via (ViaHttpApiData Int32) instance FromMisoString Int32
deriving via (ViaHttpApiData Int64) instance FromMisoString Int64
deriving via (ViaHttpApiData Integer) instance FromMisoString Integer
deriving via (ViaHttpApiData Word8) instance FromMisoString Word8
deriving via (ViaHttpApiData Word16) instance FromMisoString Word16
deriving via (ViaHttpApiData Word32) instance FromMisoString Word32
deriving via (ViaHttpApiData Word64) instance FromMisoString Word64
deriving via (ViaHttpApiData (F.Fixed a))
  instance F.HasResolution a => FromMisoString (F.Fixed a)
deriving via (ViaHttpApiData Day) instance FromMisoString Day
deriving via (ViaHttpApiData TimeOfDay) instance FromMisoString TimeOfDay
deriving via (ViaHttpApiData LocalTime) instance FromMisoString LocalTime
deriving via (ViaHttpApiData ZonedTime) instance FromMisoString ZonedTime
deriving via (ViaHttpApiData UTCTime) instance FromMisoString UTCTime
deriving via (ViaHttpApiData DayOfWeek) instance FromMisoString DayOfWeek
deriving via (ViaHttpApiData NominalDiffTime) instance FromMisoString NominalDiffTime
deriving via (ViaHttpApiData Month) instance FromMisoString Month
deriving via (ViaHttpApiData Quarter) instance FromMisoString Quarter
deriving via (ViaHttpApiData QuarterOfYear) instance FromMisoString QuarterOfYear
deriving via (ViaHttpApiData All) instance FromMisoString All
deriving via (ViaHttpApiData Any) instance FromMisoString Any
deriving via (ViaHttpApiData (Dual a))
  instance FromHttpApiData a => FromMisoString (Dual a)
deriving via (ViaHttpApiData (Sum a))
  instance FromHttpApiData a => FromMisoString (Sum a)
deriving via (ViaHttpApiData (Product a))
  instance FromHttpApiData a => FromMisoString (Product a)
deriving via (ViaHttpApiData (First a))
  instance FromHttpApiData a => FromMisoString (First a)
deriving via (ViaHttpApiData (Last a))
  instance FromHttpApiData a => FromMisoString (Last a)
deriving via (ViaHttpApiData (Semi.Min a))
  instance FromHttpApiData a => FromMisoString (Semi.Min a)
deriving via (ViaHttpApiData (Semi.Max a))
  instance FromHttpApiData a => FromMisoString (Semi.Max a)
deriving via (ViaHttpApiData (Semi.First a))
  instance FromHttpApiData a => FromMisoString (Semi.First a)
deriving via (ViaHttpApiData (Semi.Last a))
  instance FromHttpApiData a => FromMisoString (Semi.Last a)
deriving via (ViaHttpApiData (Maybe a))
  instance FromHttpApiData a => FromMisoString (Maybe a)
deriving via (ViaHttpApiData (Either a b))
  instance (FromHttpApiData a, FromHttpApiData b) => FromMisoString (Either a b)
deriving via (ViaHttpApiData UUID.UUID) instance FromMisoString UUID.UUID
deriving via (ViaHttpApiData (LenientData a))
  instance FromHttpApiData a => FromMisoString (LenientData a)
deriving via (ViaHttpApiData SetCookie) instance FromMisoString SetCookie
deriving via (ViaHttpApiData (Tagged b a))
  instance FromHttpApiData a => FromMisoString (Tagged b a)
deriving via (ViaHttpApiData (Const a b))
  instance FromHttpApiData a => FromMisoString (Const a b)
deriving via (ViaHttpApiData (Identity a))
  instance FromHttpApiData a => FromMisoString (Identity a)
----------------------------------------------------------------------------

