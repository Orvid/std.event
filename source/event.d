module std.event;

import std.traits : isCallable, isDelegate;

struct Event(OPTS...)
	if (OPTS.length >= 1 && OPTS.length <= 3 && isCallable!(OPTS[0]))
{
	import std.functional : toDelegate;
	import std.traits : ParameterTypeTuple;

	static if (OPTS.length >= 2)
	{
		static if (!is(typeof(OPTS[1]) == bool))
			static assert(0, "Expected a bool representing whether to allow duplicates!");
		public enum allowDuplicates = OPTS[1];
	}
	else
		public enum allowDuplicates = false;

	static if (OPTS.length >= 3)
	{
		static if (!is(typeof(OPTS[2]) == bool))
			static assert(0, "Expected a bool representing whether to synchronize access!");
		public enum synchronizedAccess = OPTS[2];
	}
	else
		public enum synchronizedAccess = false;

	static if (isDelegate!(OPTS[0]) || isFunction!(OPTS[0]))
		public alias DelegateType = OPTS[0];
	else
		public alias DelegateType = typeof(&OPTS[0]);

	private DelegateType[] subscribedCallbacks;
	
	static if (synchronizedAccess)
		private Object lock = new Object();
	private R MaybeSynchronous(R)(R delegate() d)
	{
		static if (synchronizedAccess)
		{
			synchronized (lock)
			{
				return d();
			}
		}
		else
			return d();
	}
	
	// This is only here because this event system is
	// designed on the C# event model, which utilizes
	// += to append a handler to an event, and the D 
	// operator for append operations is ~=, so this
	// directs them to use that instead. This may very
	// well be removed soon.
	deprecated("You should be using ~= rather than += to subscribe a callback!") void opOpAssign(string op : "+")(D value)
	{
		this ~= value;
	}
	
	void opOpAssign(string op : "~", C)(C value)
		if (isCallable!C && !isDelegate!C)
	{
		this ~= toDelegate(value);
	}
	void opOpAssign(string op : "~")(DelegateType value)
	{
		MaybeSynchronous({
			import std.algorithm : canFind;
			
			if (!allowDuplicates && subscribedCallbacks.canFind(value))
				throw new Exception("Attempted to subscribe the same callback multiple times!");
			subscribedCallbacks ~= value;
		});
	}
	
	
	void opOpAssign(string op : "-", C)(C value)
		if (isCallable!C && !isDelegate!C)
	{
		this -= toDelegate(value);
	}
	void opOpAssign(string op : "-")(DelegateType value)
	{
		MaybeSynchronous({
			import std.algorithm : countUntil, remove;
			
			auto idx = subscribedCallbacks.countUntil(value);
			if (idx == -1)
				throw new Exception("Attempted to unsubscribe a callback that was not subscribed!");
			subscribedCallbacks = subscribedCallbacks.remove(idx);
		});
	}
	
	private static void rethrowExceptionHandler(DelegateType invokedCallback, Exception exceptionThrown) { throw exceptionThrown; }
	auto opCall(ParameterTypeTuple!DelegateType args, void delegate(DelegateType, Exception) exceptionHandler = toDelegate(&rethrowExceptionHandler))
	{
		return MaybeSynchronous({
			import std.traits : ReturnType;
			
			static if (is(ReturnType!DelegateType == void))
			{
				foreach (callback; subscribedCallbacks)
				{
					try
					{
						callback(args);
					}
					catch (Exception e)
					{
						exceptionHandler(callback, e);
					}
				}
			}
			else
			{
				ReturnType!DelegateType[] retVals;
				
				foreach (callback; subscribedCallbacks)
				{
					try
					{
						retVals ~= callback(args);
					}
					catch (Exception e)
					{
						exceptionHandler(callback, e);
					}
				}
				
				return retVals;
			}
		});
	}
}

unittest
{
	import std.algorithm : equal;
	
	{
		Event!(int delegate(int i)) intReturnTest;
		int IntReturn1(int i) { return i; }
		int IntReturn2(int i) { return i; }
		static int IntReturn3(int i) { return i; }
		
		intReturnTest ~= &IntReturn1;
		intReturnTest ~= &IntReturn2;
		intReturnTest ~= &IntReturn3;
		assert(intReturnTest(3).equal([3, 3, 3]));
		intReturnTest -= &IntReturn1;
		assert(intReturnTest(4).equal([4, 4]));
		intReturnTest -= &IntReturn2;
		assert(intReturnTest(5).equal([5]));
		
		void FailIntReturn1(int i) { }
		int FailIntReturn2() { return 42; }
		static assert(!__traits(compiles, { intReturnTest ~= &FailIntReturn1; }));
		static assert(!__traits(compiles, { intReturnTest ~= &FailIntReturn2; }));
	}
	
	{
		Event!(void delegate(int i)) voidReturnTest;
		int voidTest1I = 0;
		void VoidTest1(int i) { voidTest1I = i; }
		int voidTest2I = 0;
		void VoidTest2(int i) { voidTest2I = i; }
		static int voidTest3I = 0;
		static void VoidTest3(int i) { voidTest3I = i; }
		voidReturnTest ~= &VoidTest1;
		voidReturnTest ~= &VoidTest2;
		voidReturnTest ~= &VoidTest3;
		voidReturnTest(3);
		assert(voidTest1I == 3);
		assert(voidTest2I == 3);
		assert(voidTest3I == 3);
		voidReturnTest -= &VoidTest1;
		voidReturnTest(4);
		assert(voidTest1I == 3);
		assert(voidTest2I == 4);
		assert(voidTest3I == 4);
		voidReturnTest -= &VoidTest2;
		voidReturnTest(5);
		assert(voidTest1I == 3);
		assert(voidTest2I == 4);
		assert(voidTest3I == 5);
		
		int FailVoidTest1(int i) { return i; }
		void FailVoidTest2(long i) { }
		static assert(!__traits(compiles, { voidReturnTest ~= &FailVoidTest1; }));
		static assert(!__traits(compiles, { voidReturnTest ~= &FailVoidTest2; }));
	}
	
	// TODO: test function pointers, types with static opCall's, and objects with opCall's.
	// TODO: Also test ref, inout, out, etc. param modifiers.
}
