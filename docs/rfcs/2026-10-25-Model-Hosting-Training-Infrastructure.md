
# RFC: [Model Hosting/Training Infrastructure]

| Field         | Value                       |
| ------------- | --------------------------- |
| Author        | Quinn McNamee               |
| Date          | 2026-10-25                  |
| Status        | Proposed                    |
| Decision Date | (fill when decided)         |
| Deciders      | (who agreed to the outcome) |
| Superseded By | (link, if applicable)       |

## Problem and Context

What decision is needed, why now, and what happens if the team does nothing. Write this so a newcomer to the project understands the stakes. 2 to 4 paragraphs.



The problem we are facing right now: We need to decide how we will host the AI models either for training or servicing. Hosting large language models is very expensive and we must make a choice on how we should go about running these models. This is the core resource of our project and we cannot show a working product given a non-functioning core service.

We need to make a decision on this now because two main things hang on this decision: cost and availability. If we decide late on how to run our models someone in our group will have to pay an expensive service provider. If we decide now we may able to get funding from our school to buy some of these services to host the model. Also, having an active LLM endpoint to assist us in the development of this project will immensely useful as it will be similar in performance to our finished working product.

If we do not make a choice on how we will host our model we will be left with underpowered local models that do not provide a good solution on our laptops. Another potential issue is that the LLM will not have a large enough context window to make use of our user survey results meaning the quality and integrity of our project goal could be impacted.

## Options

At least three options, **including "do nothing"**. Give each option a short name, an account of its real costs, and the condition under which it would be the right choice. An option with no such condition is a strawman, and a strawman weakens the whole document.

### Option A: [Use the school HPC]


We could ask the school and consult professors and system administrators if we could use the High Performance Cluster we have on campus. This would be the correct option as we will not have to pay for training or hosting the models. NO COSTS! We also have university support to run this sort of operation. Under the condition we have approval and we cannot get funds to pay an outside service provider this option is the correct choice as it gives us the most flexibility.

### Option B: [Pay a hosting provider]


We could pay a service provider to host/train our LLM model. The benefits of which being customer support, high availability, and not needing approval from the university to run this model. The costs however would be high as inference training is very expensive along with just hosting the model and token costs. The price can range wildly based off the approach, $50-$500 a month in server costs. This would be the appropriate option under the condition we get some sort of funding from the university and they do not want us to use the HPC.

### Option C: Do Nothing

What staying on the current path actually costs, and when that cost arrives.

We could also just do nothing. The cost of which is zero right now but the usefulness of a local model on our laptops will be very low. This will impact the usefulness of our final product and will hurt development. The quality of our service will be based on the current laptop running the program.

## Analysis


Performance is very important in this decision. Having an underpowered model will hurt our project immensely if we are trying to make something people will actually use. Complexity is somewhat important but is less of an issue as we can figure out how to use the HPC responsibly if we have to and online services will have documentation. Maintainability is also not a huge concern as the HPC rarely goes down, cloud services have good uptime, and our laptops can run a weak model locally. Security wise locally hosting a model is safest as the data does not leave our device at all, HPC coming in at 2nd as the university is not selling our data, and finally the 3rd part cloud providers have the worst security selling our data. Cost wise HPC and locally running the model both have a cost of 0 while the cloud provider can be very expensive. 


## Recommendation and Verification Plan


The HPC cluster wins in the privacy, cost, and performance categories meaning in my opinion it is the best option. We will know if this decision is the correct one given the increase tokens/s of a model ran on the HPC and uptime of the HPC. We could do some keepalive tests for our model to maintain and track uptime. 

## Constraints

The only data use concern I have is the storing of survey responses. We need to make sure it is explicitly stated that the survey responses are being stored and potentially use to train the underlying AI model. With the HPC handling data I am less concerned than I would be a cloud provider handling the data. There are no confidentiality constraints with this project.

## Delegation and Validation

- **What you handed to AI tools** on this decision, whether that was the analysis, the prototype, the tests, or the writing.

Nothing. I wrote every word in this document myself (minus the template.) Will adjust if the team reads this document with the assistance of AI.

- **What checks made that reasonable**: tests, CI, review gates, a staging environment, a rollback path. Name the ones that actually exist in your repo, not the ones you intend to build.

We do not have any checks or tests involving this decision at the moment. This is more of a project infrastructure decision. 

- **Where you stopped and validated the result yourself, and why those points.** If this decision is hard to reverse, say what you personally checked before committing to it.

The decision has not been made yet.


What is assessed is in the [AI policy](https://capstone.alexulbrich.com/assignments/introduction/#ai-policy-applies-to-every-assignment).

## Decision

Proposed, until your team decides. Then accepted, rejected, or superseded, with the date and who chaired the decision. If superseded, link the RFC that replaces this one.

Proposed decision: Go with the HPC cluster. I hope that given approval this will allow us to have lots of flexibility and performance.
