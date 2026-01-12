-- leq :: Integer -> Integer -> Integer
leq = \ x -> \ y -> 1 - (y < x) ;
one = 1 ;
main = print (leq one one) ;
