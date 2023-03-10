module CCMP

using ReactiveMP
using Random
using Distributions
import Base: prod

function Base.prod(approximation::CVI, inbound, outbound, in_marginal, nonlinearity)
    rng = something(approximation.rng, Random.default_rng())

    # Natural parameters of outbound distribution message
    η_outbound = naturalparams(outbound)

    # Natural parameter type of incoming distribution
    T = typeof(η_outbound)

    # Initial parameters of projected distribution
    λ_current = naturalparams(outbound)

    # Some distributions implement "sampling" efficient versions
    # returns the same distribution by default
    _, in_marginal_friendly = ReactiveMP.logpdf_sample_friendly(in_marginal)

    samples = ReactiveMP.cvilinearize(rand(rng, in_marginal_friendly, approximation.n_gradpoints))

    hasupdated = false

    for _ in 1:(approximation.n_iterations)
        # compute gradient of log-likelihood
        # the multiplication between two logpdfs is correct
        # we take the derivative with respect to `η`
        # `logpdf(outbound, sample)` does not depend on `η` and is just a simple scalar constant
        logq = let samples = samples, inbound = inbound, T = T
            (η) -> mean((sample) -> -logpdf(inbound, sample) * logpdf(ReactiveMP.as_naturalparams(T, η), nonlinearity(sample)), samples)
        end

        ∇logq = ReactiveMP.compute_gradient(approximation.grad, logq, vec(λ_current))

        # compute Fisher matrix 
        Fisher = ReactiveMP.compute_fisher_matrix(approximation, T, vec(λ_current))

        # compute natural gradient
        ∇f = Fisher \ ∇logq

        # compute gradient on natural parameters
        ∇ = λ_current - η_outbound - as_naturalparams(T, ∇f)

        # perform gradient descent step
        λ_new = as_naturalparams(T, ReactiveMP.cvi_update!(approximation.opt, λ_current, ∇))

        # check whether updated natural parameters are proper
        if isproper(λ_new) && ReactiveMP.enforce_proper_message(approximation.enforce_proper_messages, λ_new, η_outbound)
            λ_current = λ_new
            hasupdated = true
        end
    end

    if !hasupdated && approximation.warn
        @warn "CVI approximation has not updated the initial state. The method did not converge. Set `warn = false` to supress this warning."
    end

    return convert(Distribution, λ_current)
end

end
