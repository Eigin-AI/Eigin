Everyone approaches a spec differently. Use the structure that helps you explain your thinking. For us, a good spec makes a proposed solution easy to understand, question, and implement. These are the qualities we look for.

<!-- foldouts -->

## It's easy to read

Focus on communicating the problem, your solution, the thinking behind it, and how you would approach the work. Keep it short and use plain language. A concise spec with clear reasoning, honest limits, and an approach we can test is valuable.

## It makes the problem clear

Describe what needs to improve and why. Give the reader enough context to understand the constraints, what is outside the scope, and what success would mean for the people using the product.

## It explains the thinking

Describe your approach in plain language before getting into technical details. Explain why you chose it, which alternatives you considered, and what trade-offs you are making. Help us follow the decisions that led you there.

## It makes the design concrete

Sketch the structure, how the important parts fit together, and how they should behave. Interfaces, data flow, or pseudocode can help clarify those decisions.

## It's grounded in the codebase

Connect the proposal to what already exists. Reference relevant code and explain what you would reuse, extend, change, or remove. Show how the approach fits existing concepts and where it introduces something new. Links to specific files, interfaces, or tests help the reader follow and check your reasoning.

## It thinks through the risks

Consider meaningful edge cases, failure behavior, and assumptions. Be clear about what you know, what you have measured, and what still needs investigating. An open question is useful when you explain how you would answer it.

## It explains how to evaluate the result

Describe how we would know whether the approach works. That might involve tests, measurements, comparisons, or trying it with people. Explain what results would support your approach and what would make you reconsider it.

## It offers a path to implementation

Outline how you would organise and order the work of building and checking the solution. For a larger proposal, identify pieces that could become individual issues, what each would cover, and how they depend on one another. Include any tests or experiments that would help guide that work.

<!-- end-foldouts -->

You're welcome to work with a coding agent. What matters is that you understand the proposal and can explain the judgement behind it.

## An example

[Read an example spec](/guides/example), reconstructed from our one-off follow-up feature. It shows how a spec can explain the approach, connect it to existing code, and break the work into implementation steps.
