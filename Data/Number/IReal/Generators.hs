module Data.Number.IReal.Generators where

import Data.Number.IReal.IReal
import Data.Number.IReal.IRealOperations
import Data.Number.IReal.IntegerInterval
import Data.Number.IReal.Scalable as S
import Data.Number.IReal.Auxiliary (atDecimals)

import Test.QuickCheck
import Data.Bits (bit)
import Control.Monad (liftM, liftM2)

-- Auxiliary data type to generate random fractional parts, uniformly distributed over [0,1[.

data Dig = M | Z | P

newtype Frac = Frac [Dig]

m (Frac ds) = Frac (M : ds)
z (Frac ds) = Frac (Z : ds)
p (Frac ds) = Frac (P : ds)

ftail (Frac (_ : ds)) = Frac ds

frac  = frequency [(1,liftM m frac),
                   (2,liftM z frac),
                   (1,liftM p frac)
                  ]


nfrac = oneof [liftM m frac, liftM z nfrac]

pfrac = oneof [liftM p frac, liftM z pfrac]

instance Arbitrary Frac where
   arbitrary = frac

-- Generators ------------------------------------------------------------------

expand :: [Dig] -> Integer -> Int -> Integer
expand _       n 0 = n
expand (M : fs) n p = expand fs (2*n-1) (p-1)
expand (Z : fs) n p = expand fs (2*n)   (p-1)
expand (P : fs) n p = expand fs (2*n+1) (p-1)

genIReal :: Gen Integer -> Gen Frac -> Gen IReal
genIReal intGen fracGen = do
     n  <- intGen
     Frac fs <- fracGen
     return (ir (fromInteger . expand fs n))

instance Arbitrary IReal where
    arbitrary = genIReal arbitrary arbitrary

-- | Generates real numbers uniformly distributed over the given interval.
uniformNum :: (Integer,Integer) -> Gen IReal
uniformNum (l,u) = frequency [(1, genIReal (return l) pfrac),
                              (w, genIReal (choose (l+1,u-1)) frac),
                              (1, genIReal (return u) nfrac)
                             ]
    where w = 2*fromIntegral (u-l-1)

-- | Generates real intervals of varying width, with midpoints uniformly distributed
-- over given interval.
uniformIval :: (Integer,Integer) -> Gen IReal
uniformIval (l,u) = do
   m <- uniformNum (l,u)
   r <- uniformNum (0,1)
   n <- choose (-50,0)
   let r' = S.scale r n
   return ((m-r') -+- (m+r'))

-- | Generates random expressions built from values generated by argument generator,
--  arithmetic operators and applications of 'Floating' functions.
exprGen :: Floating a => Gen a -> Gen a
exprGen g  = gen
   where gen = frequency
          [(14,g),
           (1,liftM2 (+) gen gen),
           (1,liftM2 (*) gen gen),
           (2,liftM exp gen),
           (2,liftM cos gen),
           (2,liftM sin gen),
           (2,liftM atan gen),
           (2,liftM (sqrt . abs) gen),
           (2,liftM (log . (+1) . abs) gen)
          ]

-- Tools for testing generators  ---------------------------------------------------------

isCauchy :: IReal -> Int -> Int -> Bool
isCauchy x p r = abs (midI xpr - S.scale (midI xp) r) <= bit r
                 && isThin xp
      where xp = appr x p
            xpr = appr x (p+r)
-- | Basic test that the argument is a proper real number (is thin and satisfies
-- Cauchy criterion).
propIsRealNum x = forAll (choose (0,2000)) $ \p ->
                  forAll (choose (0,2000)) $ \r ->
                  isCauchy x p r

-- | Basic test that argument is a proper interval (the end points are proper
-- numbers, with left end smaller than right end).
propIsRealIval x =   propIsRealNum (lower x)
                    .&&. propIsRealNum (upper x)
                    .&&. (lower x <! upper x `atDecimals` 100)

-- Functionals a la Simpson --------------------------------------------------

-- universal quantification for predicates over [0,1]
forAllI :: (IReal -> Bool) -> Bool
forAllI p = pf (ctrEx pf)
   where pf fs = p (IR (fromInteger . expand (P : fs) 0))

         ctrEx pf
            | pf w      = M : ctrEx (pf . (M:))
            | otherwise = w
            where w     = P : ctrEx (pf . (P:))
