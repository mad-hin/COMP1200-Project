# 5.8 Cosine
The trigonometric functions are implemented using the CORDIC algorithm. CORDIC is an iterative method that approximates target trigonometric values through a series of rotation operations, using only additions, subtractions, and bit shifts — making it very suitable for hardware implementations. On our resource-constrained FPGA, using CORDIC increases the likelihood of meeting the very challenging 300 MHz target. Because the inputs are integers, 11 iterations are sufficient to achieve a relative error of about 5%, which also reduces hardware resource usage. CORDIC performs calculations in radians, and since sine and cosine outputs lie within [-1, 1], we use Q2.14 fixed-point format for inputs and outputs. Fixed-point representation simplifies the CORDIC implementation and Q2.14 balances precision and resource usage.

In the concrete implementation, we exploit the sine–cosine relationship and implement sine at the ALU level by reusing the cosine module:
sin(x) = cos(90° - x)

The cosine module itself consists of three submodules:
- Angle processing: maps integer input angles in [-999, 999] to a suitable range within [-90°, 90°] and converts degrees to radians in Q2.14 format.
- Core CORDIC: takes the Q2.14 radian input and outputs Q2.14 cosine/sine values.
- Output conversion: converts the Q2.14 results to BF16 format for output.

We chose BF16 as the unified output format after multiple experiments. Although IEEE-754 single precision (32-bit) was considered, achieving 300 MHz proved too difficult with 32-bit. BF16 (16-bit) provides a compact floating-point representation that meets the problem's error requirements across our various functions, so all modules output BF16.

# 5.9 Arccosine
Because the inputs are integer angles in this project, the possible outputs for arcsin/arccos are limited: only -1, 0, 1, or error are valid results. Therefore, arcsin and arccos are implemented using simple if-else checks to cover these discrete cases.

# 5.10 Sine
Sine is implemented by reusing the cosine module at the ALU level, using the identity sin(x) = cos(90° - x). This avoids duplicating the CORDIC core and saves resources.

# 5.11 Arccosine
(See 5.9) Arccosine (and arcsine) are handled by direct condition checks because input domain is integer — outputs are limited to -1, 0, 1, or error. Thus a straightforward if-else implementation suffices.

# 5.12 Tangent
Because the CORDIC core uses Q2.14 fixed-point format for speed and resource efficiency, it cannot directly produce tangent values that cover the full [-90°, 90°] range in Q2.14. We first detect the special cases tan(90°) and tan(-90°) and output an error for those. For other angles, the CORDIC core computes both sine and cosine (in Q2.14). Each is converted to BF16, and a BF16 division module computes the final tangent value as sin/cos.

# 5.13 Arctangent
Arctangent was more challenging. When implementing CORDIC we provided both rotation and vector modes, both using Q2.14. However, arctan may receive very large inputs that exceed Q2.14 range, so direct use of the Q2.14 CORDIC is insufficient. We handle this by divide-and-conquer:
- Handle cases -1, 0, 1 explicitly.
- For inputs with absolute value greater than 1, use the identity:
  arctan(a) = 90° - arctan(1/a) for a > 1
  arctan(a) = -90° - arctan(1/a) for a < -1

CORDIC requires |y| <= |x| when computing arctan(y/x), and it takes x and y as inputs. To meet the Q2.14 range limits, we set x = 1 and y = 1/a (so the CORDIC computes arctan(1/a)). Using the identities above allows computing arctan(a) for large |a|, and we finally convert the result to BF16 for output.

# 5.17 Factorial
Factorial accepts integer input and is implemented as a straightforward iterative multiplication. For internal speed we use a 32-bit unsigned integer for accumulation. The final result is converted to BF16 for output.















5.8 Cosine
5.9 Arccosine
5.10 Sine
5.11 Arccosine
5.12 Tangent
5.13 Arctangent

5.17 Factorial



三角函数的部分本质上是用了cordic算法来实现，
cordic算法是一种迭代算法，通过一系列的旋转操作来逼近目标角度的三角函数值，
且这个算法在实现中只需要进行加法、减法和位移操作，非常适合硬件实现，不用涉及更多的复杂操作
对于本次所使用的性能极度羸弱的FPGA来说，使用cordic算法让我们能够更有机会去实现300Mhz这非常困难的要求
因为输入为整数，所以在经过计算之后，只需要进行11次迭代就能够满足相对误差5%的要求，这也能相应减少硬件资源的使用，
cordic是使用弧度制进行计算的，再加上sin和cos的输出范围只是[-1,1]，
所以综合分析之后我们使用了Q2.14的定点数格式来表示输入输出，
一方面定点才能真的实现cordic算法的最简单实现，另一方面Q2.14的格式在足够满足精度的同时也能够足够少地使用硬件资源


具体实现中，首先我们利用了sin和cos的关系，在alu层就只用了cos的模块直接实现sin的计算，
即sin(x) = cos(90° - x)

然后在cos模块的具体实现中涉及了另外三个模块
第一是角度处理模块，主要是将[-999，999]的整数角度输入，换算到合理的[-90，90]度之间，再转换成Q2.14格式的弧度
第二就是最核心的cordic模块，输入为Q2.14格式的弧度，输出为Q2.14格式的cos/sin值
第三就是最后输出的换算代码，将Q2.14格式的结果转换成BF16格式输出

我们经历了几次讨论和十数日尝试，才最终真的确定可以用BF16作为统一的输出格式
这个计算器涉及的功能很多，有数字很小的三角函数功能，也有需要大数字的阶乘和次方功能
所以为了尽可能兼容，我们一开始尝试 IEEE 754 单精度浮点数格式（32位），
但发现32位对我们要实现300Mhz的工况非常非常困难，所以我们苦思冥想有没有新的办法
最后我们发现了BF16这种格式，它只用16位就能表示浮点数，在考虑到题目的要求之后
以及对数个功能的验证相对误差要求之后，我们确认BF16是可以满足我们需求的
所以我们最终决定使用BF16作为所有运算模块的输出格式

对于tan功能的实现，因为cordic模块为了足够快和够节省资源，选择了Q2.14格式，这也限制了没办法直接计算tan值
同时Q2.14格式的tan值范围非常有限，远远不能覆盖[-90，90]度之间，
所以先筛选出tan(90°)和tan(-90°)的情况，输出error
然后使用cordic模块同时计算sin和cos的值，
再将它们分别转换成BF16格式，用BF16除法模块计算出最终的tan值

因为输入只是整数角度，所以arcsin和arccos只会有四种情况，分别是-1,0,1和error
所以直接用if-else实现了

arctan是非常棘手的
一开始写cordic的时候就顺便把旋转模式和向量模式都实现了，但都是用Q2.14格式
但arctan的输入可以很大，所以直接用Q2.14格式的cordic模块无法实现
所以我们尝试分而治之，
首先，先把-1，0，1的情况先处理
这样其他的输入则变成绝对值大于1了
就可以使用
arcsin(a) = 90° - arccos(1/a)(a>1)
arcsin(a) = - 90° - arccos(1/a)(a<-1)

cordic还有隐藏条件，即需要做到|y|<=|x| 
cordic计算arctan(y/x)是需要输入x和y的   
同时还要满足Q2.14格式的范围限制
所以我们再次对输入进行了处理
把x设置为1，但y是1/x
这样cordic计算的就是arctan(1/x)
然后就可以使用上面的公式计算出arctan(x)了
最后就是再次把结果转换成BF16格式输出


对于阶乘，因为输入是整数，所以直接用一个循环乘法实现就可以了
为了内部计算快速，我们使用了32位的无符号整数来进行计算
最后把结果转换成BF16格式输出


