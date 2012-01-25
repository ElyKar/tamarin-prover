{-# LANGUAGE GeneralizedNewtypeDeriving, DeriveDataTypeable #-}
-- |
-- Copyright   : (c) 2010 Benedikt Schmidt
-- License     : GPL v3 (see LICENSE)
-- 
-- Maintainer  : Benedikt Schmidt <beschmi@gmail.com>
-- Portability : GHC only
--
-- Types and instances to handle series of disjunctions and conjunctions.
module Logic.Connectives where

import Data.Monoid
import Data.Foldable
import Data.Traversable
import Data.Typeable
import Data.Generics

import Control.Basics
import Control.Monad.Disj


-- | A conjunction of atoms of type a.
newtype Conj a = Conj { getConj :: [a] }
  deriving (Monoid, Foldable, Traversable, Eq, Ord, Show,
            Functor, Applicative, Monad, MonadPlus, Typeable, Data )

-- | A disjunction of atoms of type a.
newtype Disj a = Disj { getDisj :: [a] }
  deriving (Monoid, Foldable, Traversable, Eq, Ord, Show,
            Functor, Applicative, Monad, MonadPlus, Typeable, Data )

instance MonadDisj Disj where
    contradictoryBecause _ = Disj mzero
    disjunction m1 m2      = Disj $ getDisj m1 `mplus` getDisj m2
